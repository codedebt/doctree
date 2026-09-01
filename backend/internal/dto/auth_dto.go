package dto

import "doctree-backend/internal/model"

type DevLoginRequest struct {
	Username string `json:"username"`
}

type LoginResponse struct {
	Token string     `json:"token"`
	User  model.User `json:"user"`
}

type AuthProvider struct {
	Name   string `json:"name"`
	Issuer string `json:"issuer"`
}

type UpdateRoleRequest struct {
	Role model.Role `json:"role"`
}

type SuccessResponse struct {
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

type ErrorResponse struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type PaginatedResponse struct {
	Data     interface{} `json:"data"`
	Total    int64       `json:"total"`
	Page     int         `json:"page"`
	PageSize int         `json:"page_size"`
}
