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

func TestCatalogPipe_ConsumeMessage_Reset(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	dummy := bus.NewTestingConsumer(ctx)
	cat := pipe.NewLift("cat", dummy)

	t.Run(`reset empty`, func(t *testing.T) {

		cat.ConsumeMessage(bus.NewMessage("", map[string]map[string]string{}))
		fixture.WaitNoErrorT10(t, dummy.ExpectMessagesFn(
			bus.NewMessage("cat", map[string]string{}),
		))
	})
	t.Run(`reset with map`, func(t *testing.T) {

		cat.ConsumeMessage(bus.NewMessage("", map[string]map[string]string{
			"1": {
				"one-1": "1",
				"one-2": "2",
			},
			"2": {
				"two-1": "1",
				"two-2": "2",
			},
		}))
		fixture.WaitNoErrorT10(t, dummy.ExpectMessagesFn(
			bus.NewMessage("cat", map[string]string{}),
			bus.NewMessage("cat", map[string]string{
				"1.one-1": "1",
				"1.one-2": "2",
				"2.two-1": "1",
				"2.two-2": "2",
			}),
		))
	})
}

func TestCatalogPipe_ConsumeMessage(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	dummy := bus.NewTestingConsumer(ctx)
	cat := pipe.NewLift("cat", dummy)
	t.Run(`reset with map`, func(t *testing.T) {
		cat.ConsumeMessage(bus.NewMessage("", map[string]map[string]string{
			"1": {
				"one-1": "1",
				"one-2": "2",
			},
			"2": {
				"two-1": "1",
				"two-2": "2",
			},
		}))
		fixture.WaitNoErrorT10(t, dummy.ExpectMessagesFn(
			bus.NewMessage("cat", map[string]string{
				"1.one-1": "1",
				"1.one-2": "2",
				"2.two-1": "1",
				"2.two-2": "2",
			}),
		))
	})
	t.Run(`remove 1`, func(t *testing.T) {
		cat.ConsumeMessage(bus.NewMessage("1", nil))
		fixture.WaitNoErrorT10(t, dummy.ExpectMessagesFn(
			bus.NewMessage("cat", map[string]string{
				"1.one-1": "1",
				"1.one-2": "2",
				"2.two-1": "1",
				"2.two-2": "2",
			}),
			bus.NewMessage("cat", map[string]string{
				"2.two-1": "1",
				"2.two-2": "2",
			}),
		))
	})
	t.Run(`add 3`, func(t *testing.T) {
		cat.ConsumeMessage(bus.NewMessage("3", map[string]string{
			"three-1": "1",
		}))
		fixture.WaitNoErrorT10(t, dummy.ExpectMessagesFn(
			bus.NewMessage("cat", map[string]string{
				"1.one-1": "1",
				"1.one-2": "2",
				"2.two-1": "1",
				"2.two-2": "2",
			}),
			bus.NewMessage("cat", map[string]string{
				"2.two-1": "1",
				"2.two-2": "2",
			}),
			bus.NewMessage("cat", map[string]string{
				"2.two-1":   "1",
				"2.two-2":   "2",
				"3.three-1": "1",
			}),
		))
	})
	t.Run(`update 2`, func(t *testing.T) {
		cat.ConsumeMessage(bus.NewMessage("2", map[string]string{
			"two-3": "1",
		}))
		fixture.WaitNoErrorT10(t, dummy.ExpectMessagesFn(
			bus.NewMessage("cat", map[string]string{
				"1.one-1": "1",
				"1.one-2": "2",
				"2.two-1": "1",
				"2.two-2": "2",
			}),
			bus.NewMessage("cat", map[string]string{
				"2.two-1": "1",
				"2.two-2": "2",
			}),
			bus.NewMessage("cat", map[string]string{
				"2.two-1":   "1",
				"2.two-2":   "2",
				"3.three-1": "1",
			}),
			bus.NewMessage("cat", map[string]string{
				"2.two-3":   "1",
				"3.three-1": "1",
			}),
		))
	})
}
