package agent

import (
	"github.com/akaspin/soil/manifest"
)

type Scheduler interface {
	// SyncNamespace internal state with given manifests
	Sync(namespace string, pods []*manifest.Pod) (err error)
}

type Source interface {

	// Name returns arbiter name
	Name() string

	// Source namespaces
	Namespaces() []string

	// Mark state
	Mark() bool

	// Bind consumer. Source source will call callback on
	// change states.
	Register(callback func(active bool, env map[string]string))

	SubmitPod(name string, constraints manifest.Constraint)

	RemovePod(name string)
}