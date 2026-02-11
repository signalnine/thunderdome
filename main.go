package main

import (
	"os"

	"github.com/signalnine/thunderdome/cmd"
)

func main() {
	if err := cmd.NewRootCmd().Execute(); err != nil {
		os.Exit(1)
	}
}
