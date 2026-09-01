package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/config"
	"doctree-backend/internal/database"
	"doctree-backend/internal/handler"
	appmiddleware "doctree-backend/internal/middleware"
	"doctree-backend/internal/repository"
	"doctree-backend/internal/service"
	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
)

func main() {
	cfg, err := config.LoadConfig("")
	if err != nil {
		log.Fatalf("load configuration: %v", err)
	}

	db, err := database.InitDB(&cfg.Database)
	if err != nil {
		log.Fatalf("initialize database: %v", err)
	}

	userRepo := repository.NewUserRepository(db)
	authService := service.NewAuthService(userRepo, cfg)
	userService := service.NewUserService(userRepo)
	authHandler := handler.NewAuthHandler(authService)
	userHandler := handler.NewUserHandler(userService)
	templateRepo := repository.NewTemplateRepository(db)
	projectRepo := repository.NewProjectRepository(db)
	nodeRepo := repository.NewNodeRepository(db)
	templateService := service.NewTemplateService(templateRepo)
	projectService := service.NewProjectService(projectRepo, nodeRepo, templateRepo)
	nodeService := service.NewNodeService(nodeRepo, templateRepo, projectRepo, userRepo)
	templateHandler := handler.NewTemplateHandler(templateService, cfg.JWT.Secret)
	projectHandler := handler.NewProjectHandler(projectService, cfg.JWT.Secret)
	nodeHandler := handler.NewNodeHandler(nodeService, cfg.JWT.Secret)

	router := chi.NewRouter()
	router.Use(appmiddleware.CORSMiddleware())
	router.Use(chimiddleware.RequestID)
	router.Use(chimiddleware.RealIP)
	router.Use(chimiddleware.Logger)
	router.Use(apperr.ErrorHandlerMiddleware)

	router.Route("/api", func(r chi.Router) {
		r.Get("/health", healthHandler)
		r.Mount("/auth", authHandler.Routes())
		r.Mount("/users", userHandler.Routes(cfg.JWT.Secret))
		r.Mount("/templates", templateHandler.Routes())
		r.Route("/projects/{projectId}/nodes", func(r chi.Router) {
			r.Mount("/", nodeHandler.Routes())
		})
		r.Mount("/projects", projectHandler.Routes())
	})

	server := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("Doctree API listening on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve HTTP: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
		log.Printf("write health response: %v", err)
	}
}
