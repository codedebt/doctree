package database

import (
	"fmt"

	"doctree-backend/internal/config"
	"doctree-backend/internal/model"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	_ "modernc.org/sqlite"
)

func InitDB(cfg *config.DatabaseConfig) (*gorm.DB, error) {
	if cfg == nil {
		return nil, fmt.Errorf("database config is required")
	}
	if cfg.Driver != "sqlite" {
		return nil, fmt.Errorf("unsupported database driver %q", cfg.Driver)
	}

	db, err := gorm.Open(sqlite.New(sqlite.Config{
		DriverName: "sqlite",
		DSN:        cfg.DSN,
	}), &gorm.Config{})
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	pragmas := []string{
		"PRAGMA journal_mode=WAL;",
		"PRAGMA busy_timeout=5000;",
		"PRAGMA synchronous=NORMAL;",
		"PRAGMA cache_size=-32000;",
		"PRAGMA foreign_keys=ON;",
	}
	for _, pragma := range pragmas {
		if err := db.Exec(pragma).Error; err != nil {
			return nil, fmt.Errorf("apply SQLite pragma %q: %w", pragma, err)
		}
	}

	if err := db.AutoMigrate(
		&model.User{},
		&model.Template{},
		&model.NodeType{},
		&model.Field{},
		&model.NodeRule{},
		&model.Project{},
		&model.Node{},
		&model.NodeFieldValue{},
		&model.NodePermission{},
	); err != nil {
		return nil, fmt.Errorf("auto-migrate database: %w", err)
	}

	return db, nil
}
