package proto

//go:generate gomodifytags -override -file $GOFILE -struct NodeInfo -add-tags json -w -transform snakecase
type NodeInfo struct {
	ID        string `json:"id"`
	Advertise string `json:"advertise"`
	Version   string `json:"version"`
	API       string `json:"api"`
}

type NodesInfo []NodeInfo

func (c NodesInfo) Len() int {
	return len(c)
}

func (c NodesInfo) Less(i, j int) bool {
	return c[i].ID < c[j].ID
}

func (c NodesInfo) Swap(i, j int) {
	c[i], c[j] = c[j], c[i]
}
