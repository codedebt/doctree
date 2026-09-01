package middleware

import (
	"context"
	"net/http"
	"strings"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/model"
	"github.com/golang-jwt/jwt/v5"
)

const (
	ContextKeyUserID   = "user_id"
	ContextKeyUsername = "username"
	ContextKeyRole     = "role"
)

type authClaims struct {
	UserID   string     `json:"user_id"`
	Username string     `json:"username"`
	Role     model.Role `json:"role"`
	jwt.RegisteredClaims
}

func RequireAuth(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			parts := strings.Fields(r.Header.Get("Authorization"))
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				apperr.WriteError(w, apperr.ErrUnauthorized)
				return
			}

			claims := &authClaims{}
			token, err := jwt.ParseWithClaims(
				parts[1],
				claims,
				func(token *jwt.Token) (interface{}, error) {
					return []byte(jwtSecret), nil
				},
				jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
			)
			if err != nil || !token.Valid || claims.UserID == "" || !claims.Role.IsValid() {
				apperr.WriteError(w, apperr.ErrUnauthorized)
				return
			}

			ctx := context.WithValue(r.Context(), ContextKeyUserID, claims.UserID)
			ctx = context.WithValue(ctx, ContextKeyUsername, claims.Username)
			ctx = context.WithValue(ctx, ContextKeyRole, claims.Role)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func RequireRole(minRole model.Role) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			role := GetUserRole(r.Context())
			if !minRole.IsValid() || !role.IsValid() || !role.AtLeast(minRole) {
				apperr.WriteError(w, apperr.ErrForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func GetUserID(ctx context.Context) string {
	userID, _ := ctx.Value(ContextKeyUserID).(string)
	return userID
}

func GetUsername(ctx context.Context) string {
	username, _ := ctx.Value(ContextKeyUsername).(string)
	return username
}

func GetUserRole(ctx context.Context) model.Role {
	role, _ := ctx.Value(ContextKeyRole).(model.Role)
	return role
}
