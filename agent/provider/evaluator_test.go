//go:build ide || test_unit
// +build ide test_unit

package provider_test

import (
	"context"
	"github.com/akaspin/logx"
	"github.com/da-moon/soil/agent/allocation"
	"github.com/da-moon/soil/agent/bus"
	"github.com/da-moon/soil/agent/provider"
	"github.com/da-moon/soil/fixture"
	"github.com/da-moon/soil/lib"
	"github.com/da-moon/soil/manifest"
	"github.com/stretchr/testify/assert"
	"testing"
)

type dummyEstimator struct {
	consumer bus.Consumer
}

func (e *dummyEstimator) CreateProvider(id string, alloc *allocation.Provider) {
	e.consumer.ConsumeMessage(bus.NewMessage(id, "create"))
}

func (e *dummyEstimator) UpdateProvider(id string, alloc *allocation.Provider) {
	e.consumer.ConsumeMessage(bus.NewMessage(id, "update"))
}

func (e *dummyEstimator) DestroyProvider(id string) {
	e.consumer.ConsumeMessage(bus.NewMessage(id, "destroy"))
}

func TestEvaluator_Open(t *testing.T) {
	paths := allocation.SystemPaths{
		Local:   "testdata/etc",
		Runtime: "testdata",
	}
	var state allocation.PodSlice
	err := state.FromFilesystem(paths, allocation.GetZeroDiscoveryFunc("testdata/pod-test-1.service", "testdata/pod-test-2.service"))
	assert.NoError(t, err)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	cons := bus.NewTestingConsumer(ctx)

	evaluator := provider.NewEvaluator(ctx, logx.GetLog("test"), &dummyEstimator{cons}, state)
	assert.NoError(t, evaluator.Open())

	t.Run(`0 after recovery`, func(t *testing.T) {
		var buf lib.StaticBuffers
		assert.NoError(t, buf.ReadFiles("testdata/TestEvaluator_Open_0.hcl"))
		var pods manifest.PodSlice
		assert.NoError(t, pods.Unmarshal("private", buf.GetReaders()...))

		for _, pod := range pods {
			evaluator.Allocate(pod, map[string]string{})
		}
		fixture.WaitNoErrorT10(t, cons.ExpectMessagesFn(
			bus.NewMessage("test-1.test", "create"),
		))
	})
	t.Run(`1 -test +port`, func(t *testing.T) {
		var buf lib.StaticBuffers
		assert.NoError(t, buf.ReadFiles("testdata/TestEvaluator_Open_1.hcl"))
		var pods manifest.PodSlice
		assert.NoError(t, pods.Unmarshal("private", buf.GetReaders()...))

		for _, pod := range pods {
			evaluator.Allocate(pod, map[string]string{})
		}

		fixture.WaitNoErrorT10(t, cons.ExpectMessagesFn(
			bus.NewMessage("test-1.test", "create"),
			bus.NewMessage("test-1.port", "create"),
			bus.NewMessage("test-1.test", "destroy"),
		))
	})
	t.Run(`2 update port`, func(t *testing.T) {
		var buf lib.StaticBuffers
		assert.NoError(t, buf.ReadFiles("testdata/TestEvaluator_Open_2.hcl"))
		var pods manifest.PodSlice
		assert.NoError(t, pods.Unmarshal("private", buf.GetReaders()...))

		for _, pod := range pods {
			evaluator.Allocate(pod, map[string]string{})
		}

		fixture.WaitNoErrorT10(t, cons.ExpectMessagesFn(
			bus.NewMessage("test-1.test", "create"),
			bus.NewMessage("test-1.port", "create"),
			bus.NewMessage("test-1.test", "destroy"),
			bus.NewMessage("test-1.port", "update"),
		))
	})
	t.Run(`destroy`, func(t *testing.T) {
		evaluator.Deallocate("test-1")
		fixture.WaitNoErrorT10(t, cons.ExpectMessagesFn(
			bus.NewMessage("test-1.test", "create"),
			bus.NewMessage("test-1.port", "create"),
			bus.NewMessage("test-1.test", "destroy"),
			bus.NewMessage("test-1.port", "update"),
			bus.NewMessage("test-1.port", "destroy"),
		))
	})

	evaluator.Close()
	evaluator.Wait()
}
