// +build ide test_systemd

package command_test

import (
	"github.com/akaspin/soil/command"
	"github.com/akaspin/soil/fixture"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"net/http"
	"os"
	"sync"
	"testing"
	"time"
)

func TestAgent_Run_Stop(t *testing.T) {

	sd := fixture.NewSystemd("/run/systemd/system", "pod")
	defer sd.Cleanup()

	wd := &sync.WaitGroup{}
	wd.Add(1)

	go func() {
		defer wd.Done()
		err := command.Run(os.Stderr, os.Stdout, os.Stdin, []string{
			"agent", "--id", "node", "--meta", "rack=left", "--meta", "dc=1",
		}...)
		require.NoError(t, err)
	}()

	time.Sleep(time.Second)

	// reload
	resp, err := http.Get("http://127.0.0.1:7654/v1/agent/reload")
	assert.NoError(t, err)
	assert.Equal(t, resp.StatusCode, 200)

	// ping
	time.Sleep(time.Second)
	resp, err = http.Get("http://127.0.0.1:7654/v1/status/ping")
	assert.NoError(t, err)
	assert.Equal(t, resp.StatusCode, 200)

	resp, err = http.Get("http://127.0.0.1:7654/v1/agent/stop")
	assert.NoError(t, err)
	assert.Equal(t, resp.StatusCode, 200)

	wd.Wait()
}
