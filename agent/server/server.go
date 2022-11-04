package server

import (
	"context"
	"regexp"

	"github.com/akaspin/logx"
	"github.com/akaspin/supervisor"
	"github.com/da-moon/soil/agent/allocation"
	"github.com/da-moon/soil/agent/api"
	api_server "github.com/da-moon/soil/agent/api/api-server"
	"github.com/da-moon/soil/agent/bus"
	"github.com/da-moon/soil/agent/bus/pipe"
	"github.com/da-moon/soil/agent/cluster"
	"github.com/da-moon/soil/agent/provider"
	"github.com/da-moon/soil/agent/provision"
	"github.com/da-moon/soil/agent/resource"
	"github.com/da-moon/soil/agent/scheduler"
	"github.com/da-moon/soil/lib"
	"github.com/da-moon/soil/manifest"
	"github.com/da-moon/soil/proto"
)

var ServerVersion string

type ServerOptions struct {
	AgentId    string
	ConfigPath []string
	Address    string
	Meta       map[string]string
}

// Agent instance
type Server struct {
	ctx     context.Context
	log     *logx.Log
	options ServerOptions

	sv supervisor.Component

	confPipe  bus.Consumer
	sink      *scheduler.Sink
	kv        *cluster.KV
	api       *api_server.Router
	endpoints struct {
		registryGet    *api_server.Endpoint
		statusNodesGet *api_server.Endpoint
	}
}

func newProvisionArbiter(ctx context.Context, log *logx.Log) *scheduler.Arbiter {
	provisionArbiter := scheduler.NewArbiter(ctx, log, "provision",
		scheduler.ArbiterConfig{
			Required: manifest.Constraint{"${agent.drain}": "!= true"},
			ConstraintOnly: []*regexp.Regexp{
				regexp.MustCompile(`^provision\..+`),
			},
		})
	return provisionArbiter
}
func newProvisionDrainPipe(provisionArbiter *scheduler.Arbiter) *pipe.Divert {
	provisionDrainPipe := pipe.NewDivert(provisionArbiter, bus.NewMessage("private", map[string]string{"agent.drain": "true"}))
	return provisionDrainPipe
}
func newProvisionStrictPipe(log *logx.Log, provisionDrainPipe *pipe.Divert) *pipe.StrictPipe {
	provisionStrictPipe := pipe.NewStrict(
		"private", log, provisionDrainPipe,
		"meta",
		"system",
		"resource",  // downstream from provision evaluator
		"provision", // upstream from provision executor
	)
	return provisionStrictPipe
}
func NewServer(ctx context.Context, log *logx.Log, options ServerOptions) (s *Server) {
	s = &Server{
		ctx:     ctx,
		log:     log.GetLog("server"),
		options: options,
	}
	s.kv = cluster.NewKV(ctx, log, cluster.DefaultBackendFactory)
	// Recovery
	systemPaths := allocation.DefaultSystemPaths()
	var state allocation.PodSlice
	if recoveryErr := state.FromFilesystem(systemPaths, allocation.DefaultDbusDiscoveryFunc); recoveryErr != nil {
		s.log.Errorf("recovered with failure: %v", recoveryErr)
	}
	// provision
	provisionArbiter := newProvisionArbiter(ctx, log)
	provisionDrainPipe := newProvisionDrainPipe(provisionArbiter)
	provisionStrictPipe := newProvisionStrictPipe(log, provisionDrainPipe)
	provisionStateConsumer := pipe.NewLift("provision", pipe.NewTee(
		provisionStrictPipe,
	))
	provisionEvaluator := provision.NewEvaluator(ctx, s.log, provision.EvaluatorConfig{
		SystemPaths:    systemPaths,
		Recovery:       state,
		StatusConsumer: provisionStateConsumer,
	})
	// Resource
	resourceArbiter := scheduler.NewArbiter(ctx, log, "resource", scheduler.ArbiterConfig{
		Required: manifest.Constraint{"${agent.drain}": "!= true"},
	})
	resourceDrainPipe := pipe.NewDivert(resourceArbiter, bus.NewMessage("private", map[string]string{"agent.drain": "true"}))
	resourceStrictPipe := pipe.NewStrict(
		"private", log, resourceDrainPipe,
		"meta",
		"system",
		"provider", // resource evaluator upstream
	)
	resourceEvaluator := resource.NewEvaluator(ctx, log,
		resourceStrictPipe,
		provisionStrictPipe,
		state)

	// Provider evaluator
	providerArbiter := scheduler.NewArbiter(ctx, log, "provider", scheduler.ArbiterConfig{
		Required: manifest.Constraint{"${agent.drain}": "!= true"},
		ConstraintOnly: []*regexp.Regexp{
			regexp.MustCompile(`^provider\..+`),
			regexp.MustCompile(`^provision\..+`),
		},
	})
	providerDrainPipe := pipe.NewDivert(providerArbiter, bus.NewMessage("private", map[string]string{"agent.drain": "true"}))
	providerStrictPipe := pipe.NewStrict(
		"private", log, providerDrainPipe,
		"meta",
		"system",
	)
	providerEvaluator := provider.NewEvaluator(ctx, log, resourceEvaluator, state)

	// Meta and system

	s.confPipe = pipe.NewTee(
		providerStrictPipe,
		resourceStrictPipe,
		provisionStrictPipe,
	)

	drainFn := func(on bool) {
		providerDrainPipe.Divert(on)
		resourceDrainPipe.Divert(on)
		provisionDrainPipe.Divert(on)
	}

	s.endpoints.statusNodesGet = api.NewClusterNodesGet(log)
	s.endpoints.registryGet = api.NewRegistryPodsGet()

	// s.initRoutes()
	s.api = api_server.NewRouter(s.log,
		// status
		api.NewStatusPingGet(),
		// agent
		api.NewAgentReloadPut(s.Configure),
		api.NewAgentDrainPut(drainFn),
		api.NewAgentDrainDelete(drainFn),
		// cluster
		s.endpoints.statusNodesGet,
		// registry
		s.endpoints.registryGet,
		api.NewRegistryPodsPut(s.log, s.kv.PermanentStore("registry")),
		api.NewRegistryPodsDelete(s.log, s.kv.PermanentStore("registry")),
	)
	s.sink = scheduler.NewSink(ctx, s.log, state,
		scheduler.NewBoundedEvaluator(providerArbiter, providerEvaluator),
		scheduler.NewBoundedEvaluator(resourceArbiter, resourceEvaluator),
		scheduler.NewBoundedEvaluator(provisionArbiter, provisionEvaluator),
	)

	s.sv = supervisor.NewChain(ctx,
		s.kv,
		supervisor.NewGroup(ctx,
			providerArbiter,
			resourceArbiter,
			provisionArbiter),
		supervisor.NewGroup(ctx,
			providerEvaluator,
			resourceEvaluator,
			provisionEvaluator),
		s.sink,
		api_server.NewServer(ctx, s.log, s.options.Address, s.api),
	)
	return
}

// initRoutes initializes server request routers
// TODO(damoon) add checks to make sure this function is only called
// once, before server has started
// func (s *Server) initRoutes() {
// 	s.api = api_server.NewRouter(s.log,
// 		// status
// 		api.NewStatusPingGet(),
// 		// agent
// 		api.NewAgentReloadPut(s.Configure),
// 		api.NewAgentDrainPut(drainFn),
// 		api.NewAgentDrainDelete(drainFn),
// 		// cluster
// 		s.endpoints.statusNodesGet,
// 		// registry
// 		s.endpoints.registryGet,
// 		api.NewRegistryPodsPut(s.log, s.kv.PermanentStore("registry")),
// 		api.NewRegistryPodsDelete(s.log, s.kv.PermanentStore("registry")),
// 	)
// }
func (s *Server) Open() (err error) {
	if err = s.sv.Open(); err != nil {
		return
	}
	s.kv.Producer("nodes").Subscribe(s.ctx, pipe.NewSlice(s.log, pipe.NewTee(
		s.api,
		s.endpoints.statusNodesGet.Processor().(bus.Consumer),
	)))
	s.kv.Producer("registry").Subscribe(s.ctx, pipe.NewSlice(s.log, pipe.NewTee(
		s.sink,
		s.endpoints.registryGet.Processor().(bus.Consumer),
	)))
	s.Configure()
	return
}

func (s *Server) Close() error {
	return s.sv.Close()
}

func (s *Server) Wait() (err error) {
	return s.sv.Wait()
}

func (s *Server) Configure() {
	s.log.Infof("config: %v", s.options)
	var buffers lib.StaticBuffers
	if err := buffers.ReadFiles(s.options.ConfigPath...); err != nil {
		s.log.Errorf("error reading configs: %v", err)
	}
	serverCfg := DefaultConfig()
	serverCfg.Meta = lib.CloneMap(s.options.Meta)
	if err := serverCfg.Unmarshal(buffers.GetReaders()...); err != nil {
		s.log.Errorf("unmarshal server configs: %v", err)
	}
	var registry manifest.PodSlice
	if err := registry.Unmarshal(manifest.PrivateNamespace, buffers.GetReaders()...); err != nil {
		s.log.Errorf("unmarshal registry: %v", err)
	}
	clusterConfig := cluster.DefaultConfig()
	clusterConfig.NodeID = s.options.AgentId
	if err := (&clusterConfig).Unmarshal(buffers.GetReaders()...); err != nil {
		s.log.Errorf("unmarshal cluster config: %v", err)
	}
	s.kv.Configure(clusterConfig)
	// announce node
	s.kv.VolatileStore("nodes").ConsumeMessage(bus.NewMessage("", proto.NodeInfo{
		ID:        clusterConfig.NodeID,
		Advertise: clusterConfig.Advertise,
		Version:   proto.Version,
		API:       proto.APIV1Version,
	}))
	s.confPipe.ConsumeMessage(bus.NewMessage("meta", serverCfg.Meta))
	s.confPipe.ConsumeMessage(bus.NewMessage("system", serverCfg.System))
	s.sink.ConsumeRegistry(registry)
	s.log.Debug("configure: done")
}
