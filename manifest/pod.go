package manifest

import (
	"encoding/json"
	"hash/crc64"
	"io"
	"strings"

	"github.com/da-moon/soil/lib"
	"github.com/hashicorp/go-multierror"
	"github.com/hashicorp/hcl"
	"github.com/hashicorp/hcl/hcl/ast"
)

const (
	defaultPodTarget = "multi-user.target"
	PrivateNamespace = "private"
	PublicNamespace  = "public"
)

type PodSlice []*Pod

func (r *PodSlice) Empty() ObjectParser {
	return &Pod{
		Namespace: PrivateNamespace,
		Target:    defaultPodTarget,
		Runtime:   true,
	}
}

func (r *PodSlice) Append(v interface{}) (err error) {
	*r = append(*r, v.(*Pod))
	return
}

func (r *PodSlice) SetNamespace(namespace string) {
	for _, pod := range *r {
		pod.Namespace = namespace
	}
}

func (r *PodSlice) Unmarshal(namespace string, reader ...io.Reader) (err error) {
	err = &multierror.Error{}
	roots, parseErr := lib.ParseHCL(reader...)
	err = multierror.Append(err, parseErr)
	err = multierror.Append(err, ParseList(roots, "pod", r))
	r.SetNamespace(namespace)
	err = err.(*multierror.Error).ErrorOrNil()
	return
}

// Pod manifest
//go:generate gomodifytags -override -file $GOFILE -struct Pod -add-tags json -w -transform snakecase
type Pod struct {
	Namespace  string     `json:"namespace"`
	Name       string     `json:"name"`
	Runtime    bool       `json:"runtime"`
	Target     string     `json:"target"`
	Constraint Constraint `json:"constraint,omitempty"`
	Units      Units      `json:"units,omitempty" hcl:"-"`
	Blobs      Blobs      `json:"blobs,omitempty" hcl:"-"`
	Resources  Resources  `json:"resources,omitempty" hcl:"-"`
	Providers  Providers  `json:"providers,omitempty" hcl:"-"`
}

func (p Pod) GetID(parent ...string) string {
	return strings.Join(append(parent, p.Namespace, p.Name), ".")
}

func (p *Pod) ParseAST(raw *ast.ObjectItem) (err error) {
	err = &multierror.Error{}
	list := raw.Val.(*ast.ObjectType).List

	if err = multierror.Append(err, hcl.DecodeObject(p, raw)); err.(*multierror.Error).ErrorOrNil() != nil {
		return
	}
	p.Name = raw.Keys[0].Token.Value().(string)

	err = multierror.Append(err, ParseList([]*ast.ObjectList{list}, "unit", &p.Units))
	err = multierror.Append(err, ParseList([]*ast.ObjectList{list}, "blob", &p.Blobs))
	err = multierror.Append(err, ParseList([]*ast.ObjectList{list}, "resource", &p.Resources))
	err = multierror.Append(err, ParseList([]*ast.ObjectList{list}, "provider", &p.Providers))

	err = err.(*multierror.Error).ErrorOrNil()
	return
}

// Get Pod checksum
func (p *Pod) Mark() (res uint64) {
	buf, _ := json.Marshal(p)
	res = crc64.Checksum(buf, crc64.MakeTable(crc64.ECMA))
	return
}

// Compare
func IsEqual(left, right *Pod) (ok bool) {
	if left == nil {
		if right != nil {
			return
		}
		ok = true
		return
	}
	if left.Mark() == right.Mark() {
		ok = true
	}
	return
}
