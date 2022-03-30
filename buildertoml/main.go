package main

import (
	"fmt"
	"os"

	"github.com/BurntSushi/toml"
)

type Buildpack struct {
	Id string `toml:"id,omitempty"`
	Version string `toml:"version,omitempty"`
	Uri string `toml:"uri,omitempty"`
}

type Order struct {
	Group []Group `toml:"group"`
}

type Group struct {
	Id string `toml:"id"`
	Version string `toml:"version,omitempty"`
	optional bool `toml:"optional,omitempty"`
}

type Stack struct {
	Id string `toml:"id"`
	BuildImage string `toml:"build-image"`
	RunImage string `toml:"run-image"`
	RunImageMirrors []string `toml:"run-image-mirrors,omitempty"`
}

type Lifecycle struct {
	Version string `toml:"version,omitempty"`
	Uri string `toml:"uri,omitempty"`
}

type Builder struct {
	Description string `toml:"description,omitempty"`
	Buildpacks []Buildpack `toml:"buildpacks,omitempty"`
	Order []Order `toml:"order"`
	Stack Stack `toml:"stack"`
	Lifecycle Lifecycle `toml:"lifecycle,omitempty"`
}

func main() {
	if len(os.Args) != 2 {
		fmt.Printf("Invalid arguments: %s\n", os.Args)
		fmt.Printf("Usage: %s <lifecycle-uri>\n", os.Args[0])
		os.Exit(2)
	}
	lifecycleURI := os.Args[1]

	decoder := toml.NewDecoder(os.Stdin)
	builder := Builder{}
	_, err := decoder.Decode(&builder)
	if err != nil {
		panic(err)
	}
	builder.Lifecycle.Version = ""
	builder.Lifecycle.Uri = lifecycleURI
	encoder := toml.NewEncoder(os.Stdout)
	err = encoder.Encode(builder)
	if err != nil {
		panic(err)
	}
}
