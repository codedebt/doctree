package handler

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strconv"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/middleware"
	"doctree-backend/internal/model"
	"doctree-backend/internal/service"
	"github.com/go-chi/chi/v5"
)

type TemplateHandler struct {
	service   *service.TemplateService
	jwtSecret string
}

func NewTemplateHandler(svc *service.TemplateService, jwtSecret string) *TemplateHandler {
	return &TemplateHandler{service: svc, jwtSecret: jwtSecret}
}

func (h *TemplateHandler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Use(middleware.RequireAuth(h.jwtSecret))
	admin := middleware.RequireRole(model.RoleTemplateAdmin)

	r.Get("/", h.List)
	r.With(admin).Post("/", h.Create)
	r.With(admin).Post("/import", h.Import)
	r.Route("/{id}", func(r chi.Router) {
		r.Get("/", h.GetByID)
		r.With(admin).Put("/", h.Update)
		r.With(admin).Delete("/", h.Delete)
		r.With(admin).Post("/publish", h.Publish)
		r.With(admin).Post("/new-version", h.NewVersion)
		r.Get("/export", h.Export)

		r.Get("/node-types", h.ListNodeTypes)
		r.With(admin).Post("/node-types", h.CreateNodeType)
		r.With(admin).Put("/node-types/sort", h.SortNodeTypes)
		r.With(admin).Put("/node-types/{ntId}", h.UpdateNodeType)
		r.With(admin).Delete("/node-types/{ntId}", h.DeleteNodeType)

		r.With(admin).Post("/node-types/{ntId}/fields", h.CreateField)
		r.With(admin).Put("/node-types/{ntId}/fields/sort", h.SortFields)
		r.With(admin).Put("/node-types/{ntId}/fields/{fId}", h.UpdateField)
		r.With(admin).Delete("/node-types/{ntId}/fields/{fId}", h.DeleteField)

		r.Get("/rules", h.ListRules)
		r.With(admin).Post("/rules", h.CreateRule)
		r.With(admin).Put("/rules/{rId}", h.UpdateRule)
		r.With(admin).Delete("/rules/{rId}", h.DeleteRule)
	})
	return r
}

func (h *TemplateHandler) List(w http.ResponseWriter, r *http.Request) {
	page := positiveInt(r.URL.Query().Get("page"), 1)
	pageSize := positiveInt(r.URL.Query().Get("page_size"), 20)
	templates, total, err := h.service.List(r.URL.Query().Get("status"), page, pageSize)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	if pageSize > 100 {
		pageSize = 100
	}
	writeJSON(w, http.StatusOK, dto.PaginatedResponse{Data: templates, Total: total, Page: page, PageSize: pageSize})
}

func (h *TemplateHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req dto.CreateTemplateRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	template, err := h.service.Create(req.Name, req.Key, req.Version, req.VersionNote, middleware.GetUserID(r.Context()))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Template created", Data: template})
}

func (h *TemplateHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	template, err := h.service.GetByID(chi.URLParam(r, "id"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Template retrieved", Data: template})
}

func (h *TemplateHandler) Update(w http.ResponseWriter, r *http.Request) {
	var req dto.UpdateTemplateRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	template, err := h.service.Update(chi.URLParam(r, "id"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Template updated", Data: template})
}

func (h *TemplateHandler) Delete(w http.ResponseWriter, r *http.Request) {
	if err := h.service.SoftDelete(chi.URLParam(r, "id")); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Template deleted"})
}

func (h *TemplateHandler) Publish(w http.ResponseWriter, r *http.Request) {
	template, err := h.service.Publish(chi.URLParam(r, "id"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Template published", Data: template})
}

func (h *TemplateHandler) NewVersion(w http.ResponseWriter, r *http.Request) {
	var req dto.NewVersionRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	template, err := h.service.NewVersion(chi.URLParam(r, "id"), req.Version, req.VersionNote)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Template version created", Data: template})
}

func (h *TemplateHandler) Export(w http.ResponseWriter, r *http.Request) {
	data, err := h.service.Export(chi.URLParam(r, "id"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Template exported", Data: data})
}

func (h *TemplateHandler) Import(w http.ResponseWriter, r *http.Request) {
	var data map[string]interface{}
	if err := decodeJSON(r, &data); err != nil {
		apperr.WriteError(w, err)
		return
	}
	template, err := h.service.Import(data, middleware.GetUserID(r.Context()))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Template imported", Data: template})
}

func (h *TemplateHandler) ListNodeTypes(w http.ResponseWriter, r *http.Request) {
	nodeTypes, err := h.service.ListNodeTypes(chi.URLParam(r, "id"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Node types retrieved", Data: nodeTypes})
}

func (h *TemplateHandler) CreateNodeType(w http.ResponseWriter, r *http.Request) {
	var req dto.CreateNodeTypeRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	nt, err := h.service.CreateNodeType(chi.URLParam(r, "id"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Node type created", Data: nt})
}

func (h *TemplateHandler) UpdateNodeType(w http.ResponseWriter, r *http.Request) {
	var req dto.UpdateNodeTypeRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	nt, err := h.service.UpdateNodeType(chi.URLParam(r, "id"), chi.URLParam(r, "ntId"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Node type updated", Data: nt})
}

func (h *TemplateHandler) DeleteNodeType(w http.ResponseWriter, r *http.Request) {
	if err := h.service.DeleteNodeType(chi.URLParam(r, "id"), chi.URLParam(r, "ntId")); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Node type deleted"})
}

func (h *TemplateHandler) SortNodeTypes(w http.ResponseWriter, r *http.Request) {
	var req dto.SortRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	if err := h.service.UpdateNodeTypeSortOrder(chi.URLParam(r, "id"), req.IDs); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Node types reordered"})
}

func (h *TemplateHandler) CreateField(w http.ResponseWriter, r *http.Request) {
	var req dto.CreateFieldRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	field, err := h.service.CreateField(chi.URLParam(r, "id"), chi.URLParam(r, "ntId"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Field created", Data: field})
}

func (h *TemplateHandler) UpdateField(w http.ResponseWriter, r *http.Request) {
	var req dto.UpdateFieldRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	field, err := h.service.UpdateField(chi.URLParam(r, "id"), chi.URLParam(r, "ntId"), chi.URLParam(r, "fId"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Field updated", Data: field})
}

func (h *TemplateHandler) DeleteField(w http.ResponseWriter, r *http.Request) {
	err := h.service.DeleteField(chi.URLParam(r, "id"), chi.URLParam(r, "ntId"), chi.URLParam(r, "fId"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Field deleted"})
}

func (h *TemplateHandler) SortFields(w http.ResponseWriter, r *http.Request) {
	var req dto.SortRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	err := h.service.UpdateFieldSortOrder(chi.URLParam(r, "id"), chi.URLParam(r, "ntId"), req.IDs)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Fields reordered"})
}

func (h *TemplateHandler) ListRules(w http.ResponseWriter, r *http.Request) {
	rules, err := h.service.ListNodeRules(chi.URLParam(r, "id"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Rules retrieved", Data: rules})
}

func (h *TemplateHandler) CreateRule(w http.ResponseWriter, r *http.Request) {
	var req dto.CreateNodeRuleRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	rule, err := h.service.CreateNodeRule(chi.URLParam(r, "id"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Rule created", Data: rule})
}

func (h *TemplateHandler) UpdateRule(w http.ResponseWriter, r *http.Request) {
	var req dto.UpdateNodeRuleRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	rule, err := h.service.UpdateNodeRule(chi.URLParam(r, "id"), chi.URLParam(r, "rId"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Rule updated", Data: rule})
}

func (h *TemplateHandler) DeleteRule(w http.ResponseWriter, r *http.Request) {
	if err := h.service.DeleteNodeRule(chi.URLParam(r, "id"), chi.URLParam(r, "rId")); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Rule deleted"})
}

func decodeJSON(r *http.Request, target interface{}) error {
	decoder := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return apperr.NewBadRequest("Invalid JSON request body")
	}
	if err := decoder.Decode(&struct{}{}); !errorsIsEOF(err) {
		return apperr.NewBadRequest("Request body must contain one JSON value")
	}
	return nil
}

func errorsIsEOF(err error) bool {
	return err == io.EOF
}

func positiveInt(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 1 {
		return fallback
	}
	return parsed
}

func writeJSON(w http.ResponseWriter, status int, value interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("write JSON response: %v", err)
	}
}
