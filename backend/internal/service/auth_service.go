package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/config"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/model"
	"doctree-backend/internal/repository"
	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/oauth2"
)

const oidcStateTTL = 10 * time.Minute

type oidcState struct {
	provider  string
	expiresAt time.Time
}

type AuthService struct {
	userRepo repository.UserRepository
	config   *config.Config
	states   sync.Map
}

func NewAuthService(userRepo repository.UserRepository, cfg *config.Config) *AuthService {
	return &AuthService{userRepo: userRepo, config: cfg}
}

func (s *AuthService) DevLogin(username string) (string, *model.User, error) {
	if s.config == nil || s.config.Auth.Mode != "dev" {
		return "", nil, apperr.NewForbidden("Development login is disabled")
	}

	username = strings.TrimSpace(username)
	if username == "" {
		return "", nil, apperr.NewBadRequest("Username is required")
	}

	user, err := s.userRepo.GetByUsername(username)
	if err != nil {
		if !errors.Is(err, apperr.ErrNotFound) {
			return "", nil, err
		}

		count, countErr := s.userRepo.Count()
		if countErr != nil {
			return "", nil, countErr
		}
		role := model.RoleViewer
		if count == 0 {
			role = model.RoleSuperAdmin
		}
		user = &model.User{Username: username, Role: role, Provider: "dev"}
		if createErr := s.userRepo.Create(user); createErr != nil {
			return "", nil, createErr
		}
	}

	token, err := s.GenerateJWT(user)
	if err != nil {
		return "", nil, err
	}
	return token, user, nil
}

func (s *AuthService) GenerateJWT(user *model.User) (string, error) {
	if s.config == nil || strings.TrimSpace(s.config.JWT.Secret) == "" {
		return "", fmt.Errorf("JWT secret is not configured")
	}
	if user == nil || user.ID == "" || !user.Role.IsValid() {
		return "", fmt.Errorf("valid user is required to generate JWT")
	}

	expireHours := s.config.JWT.ExpireHours
	if expireHours <= 0 {
		expireHours = 24
	}
	now := time.Now()
	claims := jwt.MapClaims{
		"user_id":  user.ID,
		"username": user.Username,
		"role":     user.Role,
		"iat":      now.Unix(),
		"exp":      now.Add(time.Duration(expireHours) * time.Hour).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(s.config.JWT.Secret))
	if err != nil {
		return "", fmt.Errorf("sign JWT: %w", err)
	}
	return signed, nil
}

func (s *AuthService) GetJWTSecret() string {
	if s.config == nil {
		return ""
	}
	return s.config.JWT.Secret
}

func (s *AuthService) GetProviders() []dto.AuthProvider {
	providers := make([]dto.AuthProvider, 0)
	if s.config == nil {
		return providers
	}
	for _, provider := range s.config.Auth.Providers {
		providers = append(providers, dto.AuthProvider{
			Name:   provider.Name,
			Issuer: provider.Issuer,
		})
	}
	return providers
}

func (s *AuthService) OIDCLogin(providerName string) (string, error) {
	providerConfig, ok := s.findProvider(providerName)
	if !ok {
		return "", apperr.NewNotFound("Authentication provider not found")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	provider, err := oidc.NewProvider(ctx, providerConfig.Issuer)
	if err != nil {
		return "", fmt.Errorf("discover OIDC provider: %w", err)
	}

	state, err := newOIDCState()
	if err != nil {
		return "", fmt.Errorf("generate OIDC state: %w", err)
	}
	s.deleteExpiredStates()
	s.states.Store(state, oidcState{
		provider:  providerConfig.Name,
		expiresAt: time.Now().Add(oidcStateTTL),
	})

	oauthConfig := oauth2.Config{
		ClientID:     providerConfig.ClientID,
		ClientSecret: providerConfig.ClientSecret,
		RedirectURL:  providerConfig.RedirectURL,
		Endpoint:     provider.Endpoint(),
		Scopes:       []string{oidc.ScopeOpenID, "profile", "email"},
	}
	return oauthConfig.AuthCodeURL(state), nil
}

func (s *AuthService) OIDCCallback(providerName, code, state string) (string, *model.User, error) {
	if strings.TrimSpace(code) == "" || strings.TrimSpace(state) == "" {
		return "", nil, apperr.NewBadRequest("OIDC code and state are required")
	}

	storedValue, ok := s.states.LoadAndDelete(state)
	if !ok {
		return "", nil, apperr.NewBadRequest("Invalid or expired OIDC state")
	}
	storedState, ok := storedValue.(oidcState)
	if !ok || time.Now().After(storedState.expiresAt) || storedState.provider != providerName {
		return "", nil, apperr.NewBadRequest("Invalid or expired OIDC state")
	}

	providerConfig, ok := s.findProvider(providerName)
	if !ok {
		return "", nil, apperr.NewNotFound("Authentication provider not found")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	provider, err := oidc.NewProvider(ctx, providerConfig.Issuer)
	if err != nil {
		return "", nil, fmt.Errorf("discover OIDC provider: %w", err)
	}
	oauthConfig := oauth2.Config{
		ClientID:     providerConfig.ClientID,
		ClientSecret: providerConfig.ClientSecret,
		RedirectURL:  providerConfig.RedirectURL,
		Endpoint:     provider.Endpoint(),
		Scopes:       []string{oidc.ScopeOpenID, "profile", "email"},
	}
	oauthToken, err := oauthConfig.Exchange(ctx, code)
	if err != nil {
		return "", nil, apperr.ErrUnauthorized
	}
	rawIDToken, ok := oauthToken.Extra("id_token").(string)
	if !ok || rawIDToken == "" {
		return "", nil, apperr.ErrUnauthorized
	}
	idToken, err := provider.Verifier(&oidc.Config{ClientID: providerConfig.ClientID}).Verify(ctx, rawIDToken)
	if err != nil {
		return "", nil, apperr.ErrUnauthorized
	}

	var claims struct {
		Subject           string `json:"sub"`
		Email             string `json:"email"`
		Name              string `json:"name"`
		PreferredUsername string `json:"preferred_username"`
	}
	if err := idToken.Claims(&claims); err != nil || strings.TrimSpace(claims.Subject) == "" {
		return "", nil, apperr.ErrUnauthorized
	}

	user, err := s.userRepo.GetByExternalID(providerName, claims.Subject)
	if err != nil {
		if !errors.Is(err, apperr.ErrNotFound) {
			return "", nil, err
		}
		user, err = s.createOIDCUser(providerName, claims.Subject, claims.Email, claims.Name, claims.PreferredUsername)
		if err != nil {
			return "", nil, err
		}
	}

	token, err := s.GenerateJWT(user)
	if err != nil {
		return "", nil, err
	}
	return token, user, nil
}

func (s *AuthService) GetCurrentUser(userID string) (*model.User, error) {
	if strings.TrimSpace(userID) == "" {
		return nil, apperr.ErrUnauthorized
	}
	return s.userRepo.GetByID(userID)
}

func (s *AuthService) createOIDCUser(providerName, subject, email, name, preferredUsername string) (*model.User, error) {
	username := firstNonEmpty(preferredUsername, name, email, providerName+"-"+subject)
	if existing, err := s.userRepo.GetByUsername(username); err == nil && existing != nil {
		hash := sha256.Sum256([]byte(providerName + "\x00" + subject))
		username += "-" + hex.EncodeToString(hash[:4])
	} else if err != nil && !errors.Is(err, apperr.ErrNotFound) {
		return nil, err
	}

	count, err := s.userRepo.Count()
	if err != nil {
		return nil, err
	}
	role := model.RoleViewer
	if count == 0 {
		role = model.RoleSuperAdmin
	}
	user := &model.User{
		Username:   username,
		Email:      strings.TrimSpace(email),
		ExternalID: subject,
		Provider:   providerName,
		Role:       role,
	}
	if err := s.userRepo.Create(user); err != nil {
		return nil, err
	}
	return user, nil
}

func (s *AuthService) findProvider(name string) (config.OIDCProvider, bool) {
	if s.config == nil {
		return config.OIDCProvider{}, false
	}
	for _, provider := range s.config.Auth.Providers {
		if provider.Name == name {
			return provider, true
		}
	}
	return config.OIDCProvider{}, false
}

func (s *AuthService) deleteExpiredStates() {
	now := time.Now()
	s.states.Range(func(key, value interface{}) bool {
		state, ok := value.(oidcState)
		if !ok || now.After(state.expiresAt) {
			s.states.Delete(key)
		}
		return true
	})
}

func newOIDCState() (string, error) {
	buffer := make([]byte, 32)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buffer), nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value = strings.TrimSpace(value); value != "" {
			return value
		}
	}
	return ""
}
