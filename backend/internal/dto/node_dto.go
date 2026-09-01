package dto

import (
	"sort"

	"doctree-backend/internal/model"
)

type CreateNodeRequest struct {
	ParentID    string `json:"parent_id"`
	NodeTypeKey string `json:"node_type_key"`
	Name        string `json:"name"`
}

type UpdateNodeRequest struct {
	Name        *string           `json:"name,omitempty"`
	FieldValues map[string]string `json:"field_values,omitempty"`
}

type SortNodesRequest struct {
	IDs []string `json:"ids"`
}

type CreatePermissionRequest struct {
	UserID         string `json:"user_id"`
	PermissionType string `json:"permission_type"`
}

type ExportRequest struct {
	Format string `json:"format"`
}

type TreeNodeResponse struct {
	ID          string                 `json:"id"`
	ProjectID   string                 `json:"project_id"`
	ParentID    *string                `json:"parent_id"`
	NodeTypeKey string                 `json:"node_type_key"`
	Name        string                 `json:"name"`
	SortOrder   int                    `json:"sort_order"`
	FieldValues []model.NodeFieldValue `json:"field_values"`
	Children    []TreeNodeResponse     `json:"children"`
}

// BuildTree converts a flat node list into an ordered, arbitrarily deep tree.
func BuildTree(nodes []model.Node) []TreeNodeResponse {
	byID := make(map[string]model.Node, len(nodes))
	children := make(map[string][]model.Node, len(nodes))
	roots := make([]model.Node, 0)
	for _, node := range nodes {
		byID[node.ID] = node
	}
	for _, node := range nodes {
		if node.ParentID == nil {
			roots = append(roots, node)
			continue
		}
		if _, parentExists := byID[*node.ParentID]; !parentExists {
			roots = append(roots, node)
			continue
		}
		children[*node.ParentID] = append(children[*node.ParentID], node)
	}

	less := func(items []model.Node) {
		sort.SliceStable(items, func(i, j int) bool {
			if items[i].SortOrder == items[j].SortOrder {
				return items[i].CreatedAt.Before(items[j].CreatedAt)
			}
			return items[i].SortOrder < items[j].SortOrder
		})
	}
	less(roots)
	for parentID := range children {
		items := children[parentID]
		less(items)
		children[parentID] = items
	}

	var build func(model.Node, map[string]bool) TreeNodeResponse
	build = func(node model.Node, ancestors map[string]bool) TreeNodeResponse {
		response := TreeNodeResponse{
			ID: node.ID, ProjectID: node.ProjectID, ParentID: node.ParentID,
			NodeTypeKey: node.NodeTypeKey, Name: node.Name, SortOrder: node.SortOrder,
			FieldValues: node.FieldValues, Children: []TreeNodeResponse{},
		}
		if ancestors[node.ID] {
			return response
		}
		nextAncestors := make(map[string]bool, len(ancestors)+1)
		for id, present := range ancestors {
			nextAncestors[id] = present
		}
		nextAncestors[node.ID] = true
		for _, child := range children[node.ID] {
			response.Children = append(response.Children, build(child, nextAncestors))
		}
		return response
	}

	result := make([]TreeNodeResponse, 0, len(roots))
	for _, root := range roots {
		result = append(result, build(root, map[string]bool{}))
	}
	return result
}
