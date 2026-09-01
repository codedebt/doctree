package handler

import (
	"net/http"
	"strings"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/middleware"
	"doctree-backend/internal/model"
	"doctree-backend/internal/service"
	"github.com/go-chi/chi/v5"
)

type ProjectHandler struct {
	projectService *service.ProjectService
	jwtSecret      string
}

func NewProjectHandler(projectService *service.ProjectService, jwtSecret string) *ProjectHandler {
	return &ProjectHandler{projectService: projectService, jwtSecret: jwtSecret}
}

func (h *ProjectHandler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Use(middleware.RequireAuth(h.jwtSecret))
	admin := middleware.RequireRole(model.RoleProjectAdmin)

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
	})
	return r
}

func (h *ProjectHandler) List(w http.ResponseWriter, r *http.Request) {
	page := positiveInt(r.URL.Query().Get("page"), 1)
	pageSize := positiveInt(r.URL.Query().Get("page_size"), 20)
	projects, total, err := h.projectService.List(middleware.GetUserID(r.Context()), page, pageSize)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	if pageSize > 100 {
		pageSize = 100
	}
	writeJSON(w, http.StatusOK, dto.PaginatedResponse{Data: projects, Total: total, Page: page, PageSize: pageSize})
}

func (h *ProjectHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req dto.CreateProjectRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	project, err := h.projectService.Create(req.Name, req.Key, req.Description, req.Version, req.VersionNote, req.TemplateID, middleware.GetUserID(r.Context()))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Project created", Data: project})
}

func (h *ProjectHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	project, err := h.projectService.GetByID(chi.URLParam(r, "id"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Project retrieved", Data: project})
}

func (h *ProjectHandler) Update(w http.ResponseWriter, r *http.Request) {
	var req dto.UpdateProjectRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	project, err := h.projectService.Update(chi.URLParam(r, "id"), &req)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Project updated", Data: project})
}

func (h *ProjectHandler) Delete(w http.ResponseWriter, r *http.Request) {
	if err := h.projectService.SoftDelete(chi.URLParam(r, "id")); err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Project deleted"})
}

func (h *ProjectHandler) Publish(w http.ResponseWriter, r *http.Request) {
	project, err := h.projectService.Publish(chi.URLParam(r, "id"))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Project published", Data: project})
}

func (h *ProjectHandler) NewVersion(w http.ResponseWriter, r *http.Request) {
	var req dto.ProjectNewVersionRequest
	if err := decodeJSON(r, &req); err != nil {
		apperr.WriteError(w, err)
		return
	}
	project, err := h.projectService.NewVersion(chi.URLParam(r, "id"), req.Version, req.VersionNote, req.NewTemplateID)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Project version created", Data: project})
}

func (h *ProjectHandler) Export(w http.ResponseWriter, r *http.Request) {
	format := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("format")))
	if format == "" || format == "json" {
		data, err := h.projectService.ExportJSON(chi.URLParam(r, "id"))
		if err != nil {
			apperr.WriteError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "Project exported", Data: data})
		return
	}
	if format == "markdown" {
		data, err := h.projectService.ExportMarkdown(chi.URLParam(r, "id"))
		if err != nil {
			apperr.WriteError(w, err)
			return
		}
		w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(data))
		return
	}
	apperr.WriteError(w, apperr.NewBadRequest("Export format must be json or markdown"))
}

func (h *ProjectHandler) Import(w http.ResponseWriter, r *http.Request) {
	var data map[string]interface{}
	if err := decodeJSON(r, &data); err != nil {
		apperr.WriteError(w, err)
		return
	}
	project, err := h.projectService.Import(data, middleware.GetUserID(r.Context()))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, dto.SuccessResponse{Message: "Project imported", Data: project})
}
