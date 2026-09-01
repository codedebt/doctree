package handler

import (
	"net/http"
	"net/url"
	"os"
	"strings"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/middleware"
	"doctree-backend/internal/service"
	"github.com/go-chi/chi/v5"
)

const (
	oidcClientCookie   = "doctree_oidc_client"
	defaultFrontendURL = "http://localhost:3000"
)

type AuthHandler struct {
	authService *service.AuthService
}

func NewAuthHandler(authService *service.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

func (h *AuthHandler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/providers", h.GetProviders)
	r.Post("/dev-login", h.DevLogin)
	r.Get("/oidc/{provider}/login", h.OIDCLogin)
	r.Get("/oidc/{provider}/callback", h.OIDCCallback)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth(h.authService.GetJWTSecret()))
		r.Get("/me", h.GetCurrentUser)
	})
	return r
}

func (h *AuthHandler) GetProviders(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, h.authService.GetProviders())
}

func (h *AuthHandler) DevLogin(w http.ResponseWriter, r *http.Request) {
	var request dto.DevLoginRequest
	if err := decodeJSON(r, &request); err != nil {
		apperr.WriteError(w, err)
		return
	}

	token, user, err := h.authService.DevLogin(request.Username)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, dto.LoginResponse{Token: token, User: *user})
}

func (h *AuthHandler) OIDCLogin(w http.ResponseWriter, r *http.Request) {
	provider := chi.URLParam(r, "provider")
	authURL, err := h.authService.OIDCLogin(provider)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}

	client := oidcClientType(r)
	http.SetCookie(w, &http.Cookie{
		Name:     oidcClientCookie,
		Value:    client,
		Path:     "/api/auth/oidc/" + provider + "/callback",
		MaxAge:   600,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
	http.Redirect(w, r, authURL, http.StatusFound)
}

func (h *AuthHandler) OIDCCallback(w http.ResponseWriter, r *http.Request) {
	if providerError := strings.TrimSpace(r.URL.Query().Get("error")); providerError != "" {
		apperr.WriteError(w, apperr.NewBadRequest("Identity provider denied authentication"))
		return
	}

	provider := chi.URLParam(r, "provider")
	token, _, err := h.authService.OIDCCallback(
		provider,
		r.URL.Query().Get("code"),
		r.URL.Query().Get("state"),
	)
	if err != nil {
		apperr.WriteError(w, err)
		return
	}

	client := oidcClientType(r)
	if cookie, cookieErr := r.Cookie(oidcClientCookie); cookieErr == nil && cookie.Value != "" {
		client = cookie.Value
	}
	http.SetCookie(w, &http.Cookie{
		Name:     oidcClientCookie,
		Value:    "",
		Path:     "/api/auth/oidc/" + provider + "/callback",
		MaxAge:   -1,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})

	if client == "native" {
		target := &url.URL{Scheme: "doctree", Host: "auth", Path: "/callback"}
		query := target.Query()
		query.Set("token", token)
		target.RawQuery = query.Encode()
		http.Redirect(w, r, target.String(), http.StatusFound)
		return
	}

	frontendURL := strings.TrimRight(strings.TrimSpace(os.Getenv("DOCTREE_FRONTEND_URL")), "/")
	if frontendURL == "" {
		frontendURL = defaultFrontendURL
	}
	target, err := url.Parse(frontendURL + "/auth/callback")
	if err != nil {
		apperr.WriteError(w, apperr.ErrInternal)
		return
	}
	query := target.Query()
	query.Set("token", token)
	target.RawQuery = query.Encode()
	http.Redirect(w, r, target.String(), http.StatusFound)
}

func (h *AuthHandler) GetCurrentUser(w http.ResponseWriter, r *http.Request) {
	user, err := h.authService.GetCurrentUser(middleware.GetUserID(r.Context()))
	if err != nil {
		apperr.WriteError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func oidcClientType(r *http.Request) string {
	client := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("client")))
	if client == "native" || strings.EqualFold(r.URL.Query().Get("native"), "true") || r.URL.Query().Get("native") == "1" {
		return "native"
	}
	return "web"
}
