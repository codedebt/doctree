package handler

import (
	"net/http"
	"strconv"
	"strings"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/middleware"
	"doctree-backend/internal/model"
	"doctree-backend/internal/service"
	"github.com/go-chi/chi/v5"
)

type UserHandler struct {
	userService *service.UserService
}

func NewUserHandler(userService *service.UserService) *UserHandler {
	return &UserHandler{userService: userService}
}

func (h *UserHandler) Routes(jwtSecret string) chi.Router {
	r := chi.NewRouter()
	r.Use(middleware.RequireAuth(jwtSecret))
	r.Use(middleware.RequireRole(model.RoleProjectAdmin))
	r.Get("/", h.ListUsers)
	r.Post("/{id}/role", h.UpdateRole)
	return r
}

func (h *UserHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	page, err := positiveQueryInt(r, "page", 1)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	pageSizeValue := r.URL.Query().Get("pageSize")
	if pageSizeValue == "" {
		pageSizeValue = r.URL.Query().Get("page_size")
	}
	pageSize, err := parsePositiveInt(pageSizeValue, 20, "pageSize")
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	if pageSize > 100 {
		pageSize = 100
	}

	users, total, err := h.userService.ListUsers(page, pageSize)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.PaginatedResponse{
		Data:     users,
		Total:    total,
		Page:     page,
		PageSize: pageSize,
	})
}

func (h *UserHandler) UpdateRole(w http.ResponseWriter, r *http.Request) {
	var request dto.UpdateRoleRequest
	if err := decodeJSON(r, &request); err != nil {
		apperr.WriteError(w, err)
		return
	}

	err := h.userService.UpdateUserRole(
		middleware.GetUserID(r.Context()),
		middleware.GetUserRole(r.Context()),
		chi.URLParam(r, "id"),
		request.Role,
	)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.SuccessResponse{Message: "User role updated"})
}

func positiveQueryInt(r *http.Request, key string, fallback int) (int, error) {
	return parsePositiveInt(r.URL.Query().Get(key), fallback, key)
}

func parsePositiveInt(value string, fallback int, field string) (int, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 1 {
		return 0, apperr.NewBadRequest(field + " must be a positive integer")
	}
	return parsed, nil
}
