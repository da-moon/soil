package cluster

import (
	"context"
	"github.com/da-moon/soil/agent/bus"
)

type producer struct {
	key string
	kv  *KV
}

func NewProducer(kv *KV, key string) (p bus.Producer) {
	p = &producer{
		key: key,
		kv:  kv,
	}
	return
}

func (p *producer) Subscribe(ctx context.Context, consumer bus.Consumer) {
	p.kv.SubscribeKey(p.key, ctx, consumer)
}
