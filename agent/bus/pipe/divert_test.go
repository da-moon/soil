//go:build ide || test_unit
// +build ide test_unit

package pipe_test

import (
	"context"
	"github.com/da-moon/soil/agent/bus"
	"github.com/da-moon/soil/agent/bus/pipe"
	"github.com/da-moon/soil/fixture"
	"testing"
)

func TestDivert_Divert(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	dummy := bus.NewTestingConsumer(ctx)
	divertPipe := pipe.NewDivert(dummy, bus.NewMessage("drain", map[string]string{
		"drain": "true",
	}))

	t.Run("initial message", func(t *testing.T) {
		divertPipe.ConsumeMessage(bus.NewMessage("test", map[string]string{"test": "1"}))
		fixture.WaitNoErrorT(t, fixture.DefaultWaitConfig(), dummy.ExpectMessagesFn(
			bus.NewMessage("test", map[string]string{"test": "1"}),
		))
	})
	t.Run("drain on", func(t *testing.T) {
		divertPipe.Divert(true)
		fixture.WaitNoErrorT(t, fixture.DefaultWaitConfig(), dummy.ExpectMessagesFn(
			bus.NewMessage("test", map[string]string{"test": "1"}),
			bus.NewMessage("drain", map[string]string{"drain": "true"}),
		))
	})
	t.Run("message in drain mode", func(t *testing.T) {
		divertPipe.Divert(true)
		divertPipe.ConsumeMessage(bus.NewMessage("test", map[string]string{"test": "2"}))
		fixture.WaitNoErrorT(t, fixture.DefaultWaitConfig(), dummy.ExpectMessagesFn(
			bus.NewMessage("test", map[string]string{"test": "1"}),
			bus.NewMessage("drain", map[string]string{"drain": "true"}),
		))
	})
	t.Run("drain off", func(t *testing.T) {
		divertPipe.Divert(false)
		fixture.WaitNoErrorT(t, fixture.DefaultWaitConfig(), dummy.ExpectMessagesFn(
			bus.NewMessage("test", map[string]string{"test": "1"}),
			bus.NewMessage("drain", map[string]string{"drain": "true"}),
			bus.NewMessage("test", map[string]string{"test": "2"}),
		))
	})
}
