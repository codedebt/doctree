package handler

import (
	"net/http"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/middleware"
	"doctree-backend/internal/model"
	"doctree-backend/internal/service"
	"github.com/go-chi/chi/v5"
)

type NodeHandler struct {
	nodeService *service.NodeService
	jwtSecret   string
}

func NewNodeHandler(nodeService *service.NodeService, jwtSecret string) *NodeHandler {
	return &NodeHandler{nodeService: nodeService, jwtSecret: jwtSecret}
}

func (h *NodeHandler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Use(middleware.RequireAuth(h.jwtSecret))
	editorOnly := middleware.RequireRole(model.RoleEditor)
	adminOnly := middleware.RequireRole(model.RoleProjectAdmin)

	r.Get("/", h.GetTree)
	r.With(editorOnly).Post("/", h.CreateNode)
	r.With(editorOnly).Put("/sort", h.SortNodes)
	r.Route("/{nodeId}", func(r chi.Router) {
		r.With(editorOnly).Put("/", h.UpdateNode)
		r.With(editorOnly).Delete("/", h.DeleteNode)
		r.Get("/permissions", h.ListPermissions)
		r.With(adminOnly).Post("/permissions", h.CreatePermission)
		r.With(adminOnly).Delete("/permissions/{permId}", h.DeletePermission)
	})
	return r
}

func (h *NodeHandler) GetTree(w http.ResponseWriter, r *http.Request) {
	nodes, err := h.nodeService.GetTree(chi.URLParam(r, "projectId"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Project tree retrieved", Data: dto.BuildTree(nodes)})
}

func (h *NodeHandler) CreateNode(w http.ResponseWriter, r *http.Request) {
	var req dto.CreateNodeRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	if err := h.requireNodeInProject(chi.URLParam(r, "projectId"), req.ParentID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	if err := h.requireNodePermission(r, req.ParentID, "editor"); err != nil {
		apperr.WriteError(w, err)
		return
	}
	node, err := h.nodeService.CreateNode(chi.URLParam(r, "projectId"), req.ParentID, req.NodeTypeKey, req.Name)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Node created", Data: node})
}

func (h *NodeHandler) UpdateNode(w http.ResponseWriter, r *http.Request) {
	projectID, nodeID := chi.URLParam(r, "projectId"), chi.URLParam(r, "nodeId")
	if err := h.requireNodeInProject(projectID, nodeID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	if err := h.requireNodePermission(r, nodeID, "editor"); err != nil {
		apperr.WriteError(w, err)
		return
	}
	var req dto.UpdateNodeRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	node, err := h.nodeService.UpdateNode(nodeID, &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Node updated", Data: node})
}

func (h *NodeHandler) DeleteNode(w http.ResponseWriter, r *http.Request) {
	projectID, nodeID := chi.URLParam(r, "projectId"), chi.URLParam(r, "nodeId")
	if err := h.requireNodeInProject(projectID, nodeID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	if err := h.requireNodePermission(r, nodeID, "editor"); err != nil {
		apperr.WriteError(w, err)
		return
	}
	if err := h.nodeService.DeleteNode(nodeID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Node deleted"})
}

func (h *NodeHandler) SortNodes(w http.ResponseWriter, r *http.Request) {
	var req dto.SortNodesRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	if err := h.nodeService.UpdateSortOrder(chi.URLParam(r, "projectId"), req.IDs); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Nodes reordered"})
}

func (h *NodeHandler) CreatePermission(w http.ResponseWriter, r *http.Request) {
	projectID, nodeID := chi.URLParam(r, "projectId"), chi.URLParam(r, "nodeId")
	if err := h.requireNodeInProject(projectID, nodeID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	var req dto.CreatePermissionRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	permission, err := h.nodeService.CreatePermission(nodeID, req.UserID, req.PermissionType)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Permission created", Data: permission})
}

func (h *NodeHandler) DeletePermission(w http.ResponseWriter, r *http.Request) {
	projectID, nodeID := chi.URLParam(r, "projectId"), chi.URLParam(r, "nodeId")
	if err := h.requireNodeInProject(projectID, nodeID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	permissions, err := h.nodeService.ListPermissions(nodeID)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	permissionID := chi.URLParam(r, "permId")
	found := false
	for _, permission := range permissions {
		if permission.ID == permissionID {
			found = true
			break
		}
	}
	if !found {
		apperr.WriteError(w, apperr.ErrNotFound)
		return
	}
	if err := h.nodeService.DeletePermission(permissionID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Permission deleted"})
}

func (h *NodeHandler) ListPermissions(w http.ResponseWriter, r *http.Request) {
	projectID, nodeID := chi.URLParam(r, "projectId"), chi.URLParam(r, "nodeId")
	if err := h.requireNodeInProject(projectID, nodeID); err != nil {
		apperr.WriteError(w, err)
		return
	}
	permissions, err := h.nodeService.ListPermissions(nodeID)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Permissions retrieved", Data: permissions})
}

func (h *NodeHandler) requireNodePermission(r *http.Request, nodeID, requiredPerm string) error {
	allowed, err := h.nodeService.CheckPermission(
		nodeID,
		middleware.GetUserID(r.Context()),
		requiredPerm,
		middleware.GetUserRole(r.Context()),
	)
	if err != nil {
		return err
	}
	if !allowed {
		return apperr.ErrForbidden
	}
	return nil
}

func (h *NodeHandler) requireNodeInProject(projectID, nodeID string) error {
	nodes, err := h.nodeService.GetTree(projectID)
	if err != nil {
		return err
	}
	for _, node := range nodes {
		if node.ID == nodeID {
			return nil
		}
	}
	return apperr.ErrNotFound
}
