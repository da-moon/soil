package manifest

import (
	"strings"

	"github.com/hashicorp/hcl"
	"github.com/hashicorp/hcl/hcl/ast"
)

type Units []Unit

func (u *Units) Empty() ObjectParser {
	return &Unit{
		Transition: Transition{
			Create:  "start",
			Update:  "restart",
			Destroy: "stop",
		},
	}
}

func (u *Units) Append(v interface{}) (err error) {
	v1 := v.(*Unit)
	*u = append(*u, *v1)
	return
}

//go:generate gomodifytags -override -file $GOFILE -struct Unit -add-tags json -w -transform snakecase
type Unit struct {
	Transition `json:"transition,omitempty" hcl:",squash"`
	Name       string `json:"name"`
	Source     string `json:"source"`
}

func (u Unit) GetID(parent ...string) string {
	return strings.Join(append(parent, u.Name), ".")
}

func (u *Unit) ParseAST(raw *ast.ObjectItem) (err error) {
	u.Name = raw.Keys[0].Token.Value().(string)
	err = hcl.DecodeObject(u, raw)
	u.Source = Heredoc(u.Source)
	return
}

// Unit transition
//go:generate gomodifytags -override -file $GOFILE -struct Transition -add-tags json -w -transform snakecase
type Transition struct {
	Create    string `json:"create,omitempty"`
	Update    string `json:"update,omitempty"`
	Destroy   string `json:"destroy,omitempty"`
	Permanent bool   `json:"permanent,omitempty"`
}
