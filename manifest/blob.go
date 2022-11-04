package manifest

import (
	"strings"

	"github.com/hashicorp/hcl"
	"github.com/hashicorp/hcl/hcl/ast"
)

type Blobs []Blob

func (b *Blobs) Empty() ObjectParser {
	return &Blob{
		Permissions: 0644,
	}
}

func (b *Blobs) Append(v interface{}) (err error) {
	v1 := v.(*Blob)
	*b = append(*b, *v1)
	return
}

// Pod file
//go:generate gomodifytags -override -file $GOFILE -struct Blob -add-tags json -w -transform snakecase
type Blob struct {
	Name        string `json:"name"`
	Source      string `json:"source"`
	Permissions int    `json:"permissions,omitempty"`
	Leave       bool   `json:"leave,omitempty"`
}

func (b Blob) GetID(parent ...string) string {
	return strings.Join(append(parent, b.Name), ".")
}

func (b *Blob) ParseAST(raw *ast.ObjectItem) (err error) {
	b.Name = raw.Keys[0].Token.Value().(string)
	err = hcl.DecodeObject(b, raw)
	b.Source = Heredoc(b.Source)
	return
}
