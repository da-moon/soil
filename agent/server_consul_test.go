//go:build ide || (test_systemd && !test_without_cluster)
// +build ide test_systemd,!test_without_cluster

package agent_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"github.com/akaspin/logx"
	"github.com/da-moon/soil/agent"
	"github.com/da-moon/soil/fixture"
	"github.com/da-moon/soil/lib"
	"github.com/da-moon/soil/manifest"
	"github.com/da-moon/soil/proto"
	"github.com/hashicorp/consul/api"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"net/http"
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestServer_Configure_Consul(t *testing.T) {
	fixture.DestroyUnits("pod-*", "unit-*")
	defer fixture.DestroyUnits("pod-*", "unit-*")

	os.RemoveAll("testdata/.test_server.hcl")

	log := logx.GetLog("test")
	serverOptions := agent.ServerOptions{
		ConfigPath: []string{
			"testdata/.test_server.hcl",
		},
		Meta:    map[string]string{},
		Address: fmt.Sprintf(":%d", fixture.RandomPort(t)),
	}
	server := agent.NewServer(context.Background(), log, serverOptions)
	defer server.Close()

	consulServer := fixture.NewConsulServer(t, nil)
	defer consulServer.Clean()
	consulServer.Up()
	consulServer.WaitLeader()
	consulServer.Pause()

	cli, cliErr := api.NewClient(&api.Config{
		Address: consulServer.Address(),
	})
	assert.NoError(t, cliErr)

	configEnv := map[string]interface{}{
		"ConsulAddress": consulServer.Address(),
		"AgentAddress":  fmt.Sprintf("%s%s", fixture.GetLocalIP(t), serverOptions.Address),
	}
	allUnitNames := []string{
		"pod-*",
		"unit-*",
	}

	t.Run(`start agent`, func(t *testing.T) {
		require.NoError(t, server.Open())
	})
	t.Run(`0 configure with consul`, func(t *testing.T) {
		writeConfig(t, "testdata/TestServer_Configure_Consul_0.hcl", configEnv)
		server.Configure()
		fixture.WaitNoErrorT10(t, fixture.UnitStatesFn(allUnitNames, map[string]string{
			"pod-private-1.service": "active",
			"unit-1.service":        "active",
		}))
	})
	t.Run(`unpause consul server`, func(t *testing.T) {
		consulServer.Unpause()
	})
	t.Run(`ensure node announced`, func(t *testing.T) {
		fixture.WaitNoErrorT10(t, func() (err error) {
			res, _, err := cli.KV().List("soil/nodes", nil)
			if err != nil {
				return
			}
			if len(res) != 1 {
				err = fmt.Errorf(`node registration not found`)
			}
			var found bool
			for _, raw := range res {
				var node proto.NodeInfo
				if err = json.NewDecoder(bytes.NewReader(raw.Value)).Decode(&node); err != nil {
					return
				}
				if node.ID == "node" && node.Advertise == configEnv["AgentAddress"] {
					found = true
					break
				}
			}
			if !found {
				err = fmt.Errorf(`node not found`)
			}
			return
		})
	})
	t.Run(`ping node`, func(t *testing.T) {
		fixture.WaitNoErrorT10(t, func() (err error) {
			resp, err := http.Get(fmt.Sprintf("http://%s/v1/status/ping?node=node", configEnv["AgentAddress"]))
			if err != nil {
				return
			}
			if resp == nil {
				err = fmt.Errorf(`no resp`)
				return
			}
			if resp.StatusCode != 200 {
				err = fmt.Errorf(`bad status code: %d`, resp.StatusCode)
			}
			return
		})
	})
	t.Run(`get nodes`, func(t *testing.T) {
		fixture.WaitNoErrorT10(t, func() (err error) {
			resp, err := http.Get(fmt.Sprintf("http://%s/v1/status/nodes", configEnv["AgentAddress"]))
			if err != nil {
				return
			}
			if resp == nil {
				err = fmt.Errorf(`no resp`)
				return
			}
			if resp.StatusCode != 200 {
				err = fmt.Errorf(`bad status code: %d`, resp.StatusCode)
				return
			}
			var v proto.NodesInfo
			if err = json.NewDecoder(resp.Body).Decode(&v); err != nil {
				return
			}
			defer resp.Body.Close()
			if len(v) == 0 {
				err = fmt.Errorf(`no nodes`)
				return
			}
			if v[0].ID != "node" {
				err = fmt.Errorf(`bad node id: %v`, v)
			}
			return
		})
	})
	t.Run(`10 put /v1/registry`, func(t *testing.T) {
		var pods manifest.PodSlice
		rs := &lib.StaticBuffers{}
		require.NoError(t, rs.ReadFiles("testdata/TestServer_Configure_Consul_10.hcl"))
		require.NoError(t, pods.Unmarshal(manifest.PublicNamespace, rs.GetReaders()...))

		buf := &bytes.Buffer{}
		assert.NoError(t, json.NewEncoder(buf).Encode(pods))
		req, err := http.NewRequest(http.MethodPut, fmt.Sprintf("http://%s/v1/registry", configEnv["AgentAddress"]), bytes.NewReader(buf.Bytes()))
		require.NoError(t, err)
		resp, err := http.DefaultClient.Do(req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		assert.Equal(t, resp.StatusCode, 200)
	})
	t.Run(`get /v1/registry`, func(t *testing.T) {
		var pods manifest.PodSlice
		rs := &lib.StaticBuffers{}
		require.NoError(t, rs.ReadFiles("testdata/TestServer_Configure_Consul_10.hcl"))
		require.NoError(t, pods.Unmarshal(manifest.PublicNamespace, rs.GetReaders()...))

		fixture.WaitNoErrorT10(t, func() (err error) {
			resp, err := http.Get(fmt.Sprintf("http://%s/v1/registry", configEnv["AgentAddress"]))
			if err != nil {
				return
			}
			if resp == nil {
				err = fmt.Errorf(`response is nil`)
				return
			}
			if resp.StatusCode != 200 {
				err = fmt.Errorf(`bad status code: %d`, resp.StatusCode)
				return
			}
			var res manifest.PodSlice
			if err = json.NewDecoder(resp.Body).Decode(&res); err != nil {
				return
			}
			defer resp.Body.Close()
			if !reflect.DeepEqual(res, pods) {
				err = fmt.Errorf(`not equal: (expect)%v != (actual)%v`, pods, res)
			}
			return
		})
	})
	t.Run(`ensure public pods`, func(t *testing.T) {
		fixture.WaitNoErrorT10(t, fixture.UnitStatesFn(allUnitNames, map[string]string{
			"pod-private-1.service":       "active",
			"unit-1.service":              "active",
			"pod-public-1-public.service": "active",
			"unit-1-public.service":       "active",
			"pod-public-2-public.service": "active",
			"unit-2-public.service":       "active",
		}))
	})
	t.Run(`delete /v1/registry 2-public`, func(t *testing.T) {
		req, err := http.NewRequest(http.MethodDelete, fmt.Sprintf("http://%s/v1/registry", configEnv["AgentAddress"]), strings.NewReader(`["2-public"]`))
		require.NoError(t, err)
		resp, err := http.DefaultClient.Do(req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		assert.Equal(t, resp.StatusCode, 200)
	})
	t.Run(`11 get /v1/registry`, func(t *testing.T) {
		var pods manifest.PodSlice
		rs := &lib.StaticBuffers{}
		require.NoError(t, rs.ReadFiles("testdata/TestServer_Configure_Consul_11.hcl"))
		require.NoError(t, pods.Unmarshal(manifest.PublicNamespace, rs.GetReaders()...))

		fixture.WaitNoErrorT10(t, func() (err error) {
			resp, err := http.Get(fmt.Sprintf("http://%s/v1/registry", configEnv["AgentAddress"]))
			if err != nil {
				return
			}
			if resp == nil {
				err = fmt.Errorf(`response is nil`)
				return
			}
			if resp.StatusCode != 200 {
				err = fmt.Errorf(`bad status code: %d`, resp.StatusCode)
				return
			}
			var res manifest.PodSlice
			if err = json.NewDecoder(resp.Body).Decode(&res); err != nil {
				return
			}
			defer resp.Body.Close()
			if !reflect.DeepEqual(res, pods) {
				err = fmt.Errorf(`not equal: (expect)%v != (actual)%v`, pods, res)
			}
			return
		})
	})
	t.Run(`ensure 2-public is removed`, func(t *testing.T) {
		fixture.WaitNoErrorT10(t, fixture.UnitStatesFn(allUnitNames, map[string]string{
			"pod-private-1.service":       "active",
			"unit-1.service":              "active",
			"pod-public-1-public.service": "active",
			"unit-1-public.service":       "active",
		}))
	})
}
