package allocation

import (
	"encoding/json"
	"fmt"
	"github.com/da-moon/soil/manifest"
	"github.com/hashicorp/go-multierror"
	"github.com/mitchellh/copystructure"
	"io"
	"strings"
)

const (
	resourceSpecPrefix    = "### RESOURCE "
	ResourceValuesPostfix = "__values"
)

// Allocation resources
type ResourceSlice []*Resource

func (s *ResourceSlice) GetEmpty(paths SystemPaths) (empty Asset) {
	empty = &Resource{}
	return
}

func (s *ResourceSlice) GetVersionPrefix(v string) (p string) {
	p = resourceSpecPrefix
	return
}

func (r *ResourceSlice) FromManifest(m manifest.Pod, env manifest.FlatMap) (err error) {
	err = &multierror.Error{}
	for _, decl := range m.Resources {
		v, _ := copystructure.Copy(decl)
		var resource Resource
		if err1 := (&resource).FromManifest(m.Name, v.(manifest.Resource), env); err1 != nil {
			err = multierror.Append(err, err1)
		}
		*r = append(*r, &resource)
	}
	err = err.(*multierror.Error).ErrorOrNil()
	return
}

func (r *ResourceSlice) AppendItem(v Asset) {
	*r = append(*r, v.(*Resource))
}

// Allocated resource
type Resource struct {
	// Requested resource
	Request manifest.Resource

	// Allocated values stored in "resource.pod-name.<provider-name>.<resource-name>.__values" environment
	Values manifest.FlatMap `json:",omitempty"`
}

func (r Resource) String() string {
	return fmt.Sprint(r.Request, r.Values)
}

// Unmarshal resource allocation from manifest
func (r *Resource) FromManifest(podName string, req manifest.Resource, env manifest.FlatMap) (err error) {
	r.Request = req

	// try to recover values from env
	if values, ok := env["resource."+podName+"."+r.ValuesKey()]; ok {
		err = json.Unmarshal([]byte(values), &r.Values)
	}
	return
}

// Returns values bag key without provider
func (r *Resource) ValuesKey() (res string) {
	res = r.Request.Name + "." + ResourceValuesPostfix
	return
}

// Marshal resource line
func (r *Resource) MarshalSpec(w io.Writer) (err error) {
	if _, err = fmt.Fprint(w, resourceSpecPrefix); err != nil {
		return
	}
	err = json.NewEncoder(w).Encode(r)
	return
}

func (r *Resource) UnmarshalSpec(line string, spec Spec, paths SystemPaths) (err error) {
	// old resources are skipped
	err = json.Unmarshal([]byte(strings.TrimPrefix(line, resourceSpecPrefix)), r)
	return
}

func (r *Resource) Clone() (res *Resource) {
	i, _ := copystructure.Copy(r)
	res = i.(*Resource)
	return
}
