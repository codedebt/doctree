package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

const defaultConfigPath = "./config.yaml"

type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	Auth     AuthConfig     `yaml:"auth"`
	JWT      JWTConfig      `yaml:"jwt"`
}

type ServerConfig struct {
	Port int `yaml:"port"`
}

type DatabaseConfig struct {
	Driver string `yaml:"driver"`
	DSN    string `yaml:"dsn"`
}

type AuthConfig struct {
	Mode      string         `yaml:"mode"`
	Providers []OIDCProvider `yaml:"providers"`
}

type OIDCProvider struct {
	Name         string `yaml:"name"`
	Issuer       string `yaml:"issuer"`
	ClientID     string `yaml:"client_id"`
	ClientSecret string `yaml:"client_secret"`
	RedirectURL  string `yaml:"redirect_url"`
}

type JWTConfig struct {
	Secret      string `yaml:"secret"`
	ExpireHours int    `yaml:"expire_hours"`
}

func LoadConfig(path string) (*Config, error) {
	if envPath := os.Getenv("DOCTREE_CONFIG"); envPath != "" {
		path = envPath
	} else if path == "" {
		path = defaultConfigPath
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config %q: %w", path, err)
	}

	cfg := &Config{
		Server: ServerConfig{Port: 8080},
		Database: DatabaseConfig{
			Driver: "sqlite",
			DSN:    "./doctree.db",
		},
		Auth: AuthConfig{Mode: "dev", Providers: []OIDCProvider{}},
		JWT:  JWTConfig{ExpireHours: 24},
	}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse config %q: %w", path, err)
	}

	return cfg, nil
}
