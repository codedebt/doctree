package middleware

import (
	"net/http"
	"os"
	"strings"

	"github.com/rs/cors"
)

func CORSMiddleware() func(http.Handler) http.Handler {
	origins := []string{"*"}
	if configured := strings.TrimSpace(os.Getenv("DOCTREE_ALLOWED_ORIGINS")); configured != "" {
		origins = origins[:0]
		for _, origin := range strings.Split(configured, ",") {
			if origin = strings.TrimSpace(origin); origin != "" {
				origins = append(origins, origin)
			}
		}
		if len(origins) == 0 {
			origins = []string{"*"}
		}
	}

	return cors.New(cors.Options{
		AllowedOrigins: origins,
		AllowedMethods: []string{
			http.MethodGet,
			http.MethodPost,
			http.MethodPut,
			http.MethodPatch,
			http.MethodDelete,
			http.MethodOptions,
		},
		AllowedHeaders: []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		MaxAge:         300,
	}).Handler
}
