package main

import (
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/signalnine/conclave/internal/proxy"
	"github.com/spf13/cobra"
)

var proxyCmd = &cobra.Command{
	Use:   "proxy",
	Short: "Token-counting reverse proxy for Anthropic API",
	Long:  "Transparent HTTP reverse proxy that counts input/output tokens from Anthropic API responses.",
	RunE:  runProxy,
}

func init() {
	proxyCmd.Flags().Int("port", 8199, "Port to listen on")
	proxyCmd.Flags().String("target", "https://api.anthropic.com", "Target API URL to proxy to")
	rootCmd.AddCommand(proxyCmd)
}

func runProxy(cmd *cobra.Command, args []string) error {
	port, _ := cmd.Flags().GetInt("port")
	target, _ := cmd.Flags().GetString("target")

	counter := &proxy.TokenCounter{}

	rp, err := proxy.New(target, counter)
	if err != nil {
		return fmt.Errorf("create proxy: %w", err)
	}

	addr := fmt.Sprintf("localhost:%d", port)
	server := &http.Server{
		Addr:    addr,
		Handler: rp,
	}

	// Signal handling for clean shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigCh
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprint(os.Stderr, counter.Summary())
		server.Close()
	}()

	fmt.Fprintf(os.Stderr, "Proxy listening on http://%s → %s\n", addr, target)
	fmt.Fprintf(os.Stderr, "Export: ANTHROPIC_BASE_URL=http://%s\n\n", addr)

	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		return fmt.Errorf("server: %w", err)
	}

	return nil
}
