package apperr

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
)

type AppError struct {
	Code       string `json:"code"`
	Message    string `json:"message"`
	HTTPStatus int    `json:"-"`
}

func (e *AppError) Error() string { return e.Message }

var (
	ErrNotFound     = &AppError{Code: "NOT_FOUND", Message: "Resource not found", HTTPStatus: http.StatusNotFound}
	ErrForbidden    = &AppError{Code: "FORBIDDEN", Message: "Access denied", HTTPStatus: http.StatusForbidden}
	ErrUnauthorized = &AppError{Code: "UNAUTHORIZED", Message: "Authentication required", HTTPStatus: http.StatusUnauthorized}
	ErrBadRequest   = &AppError{Code: "BAD_REQUEST", Message: "Invalid request", HTTPStatus: http.StatusBadRequest}
	ErrConflict     = &AppError{Code: "CONFLICT", Message: "Resource conflict", HTTPStatus: http.StatusConflict}
	ErrInternal     = &AppError{Code: "INTERNAL_ERROR", Message: "Internal server error", HTTPStatus: http.StatusInternalServerError}
)

func NewBadRequest(msg string) *AppError {
	return &AppError{Code: ErrBadRequest.Code, Message: msg, HTTPStatus: ErrBadRequest.HTTPStatus}
}

func NewNotFound(msg string) *AppError {
	return &AppError{Code: ErrNotFound.Code, Message: msg, HTTPStatus: ErrNotFound.HTTPStatus}
}

func NewForbidden(msg string) *AppError {
	return &AppError{Code: ErrForbidden.Code, Message: msg, HTTPStatus: ErrForbidden.HTTPStatus}
}

func NewConflict(msg string) *AppError {
	return &AppError{Code: ErrConflict.Code, Message: msg, HTTPStatus: ErrConflict.HTTPStatus}
}

func WriteError(w http.ResponseWriter, err error) {
	appError := ErrInternal
	var target *AppError
	if errors.As(err, &target) {
		appError = target
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(appError.HTTPStatus)
	if encodeErr := json.NewEncoder(w).Encode(appError); encodeErr != nil {
		log.Printf("write error response: %v", encodeErr)
	}
}

func ErrorHandlerMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				if err, ok := recovered.(error); ok {
					var appError *AppError
					if errors.As(err, &appError) {
						WriteError(w, appError)
						return
					}
					log.Printf("recovered panic: %v", err)
				} else {
					log.Printf("recovered panic: %v", recovered)
				}
				WriteError(w, ErrInternal)
			}
		}()

		next.ServeHTTP(w, r)
	})
}
