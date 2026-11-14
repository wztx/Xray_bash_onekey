package deploy

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"math/big"
	"net"
	"os"
	"testing"
	"time"

	"github.com/hello-yunshu/Xray_bash_onekey/internal/xraycfg"
)

func stubProbe(t *testing.T, fn func(ctx context.Context, target, sni string) error) *int {
	t.Helper()
	old := probeOrigin
	calls := 0
	probeOrigin = func(ctx context.Context, target, sni string) error {
		calls++
		return fn(ctx, target, sni)
	}
	t.Cleanup(func() { probeOrigin = old })
	return &calls
}

func TestEditTargetProbesEffectiveOrigin(t *testing.T) {
	root, configPath, old := editSandbox(t)
	stubXrayTest(t, func(context.Context, string, string) error { return nil })
	var gotTarget, gotSNI string
	stubProbe(t, func(_ context.Context, target, sni string) error {
		gotTarget, gotSNI = target, sni
		return nil
	})
	report, err := EditConfig(context.Background(), EditSpec{
		Root: root, Request: xraycfg.EditRequest{ServerNames: []string{"www.example.org"}}, NoRestart: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if gotSNI != "www.example.org" {
		t.Fatalf("sni = %q", gotSNI)
	}
	if gotTarget != "example.com:443" {
		t.Fatalf("target = %q, want the installed target unchanged", gotTarget)
	}
	if report.OriginProbe == "" {
		t.Fatal("report must record the successful probe")
	}
	newBody, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(newBody) == string(old) {
		t.Fatal("config should have changed")
	}
}

func TestEditTargetProbeFailureWritesNothing(t *testing.T) {
	root, configPath, old := editSandbox(t)
	stubXrayTest(t, func(context.Context, string, string) error { return nil })
	stubProbe(t, func(context.Context, string, string) error {
		return ErrOriginUnreachable
	})
	_, err := EditConfig(context.Background(), EditSpec{
		Root: root, Request: xraycfg.EditRequest{Target: "origin.invalid:443"}, NoRestart: true,
	})
	if !errors.Is(err, ErrOriginUnreachable) {
		t.Fatalf("err = %v, want ErrOriginUnreachable", err)
	}
	body, readErr := os.ReadFile(configPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(body) != string(old) {
		t.Fatal("probe failure must not modify the live config")
	}
	entries, _ := os.ReadDir(root + "/etc/idleleo/backup")
	if len(entries) != 0 {
		t.Fatalf("probe failure must not write a backup, got %d entries", len(entries))
	}
}

func TestEditPortDoesNotProbeOrigin(t *testing.T) {
	root, _, _ := editSandbox(t)
	stubXrayTest(t, func(context.Context, string, string) error { return nil })
	calls := stubProbe(t, func(context.Context, string, string) error {
		return errors.New("must not be called")
	})
	if _, err := EditConfig(context.Background(), EditSpec{
		Root: root, Request: xraycfg.EditRequest{Port: 8080}, NoRestart: true,
	}); err != nil {
		t.Fatal(err)
	}
	if *calls != 0 {
		t.Fatalf("port edit probed the origin %d times", *calls)
	}
}

func TestDefaultProbeOriginTLSLocal(t *testing.T) {
	srv := tlsListener(t)
	defer srv.Close()
	addr := srv.Addr().String()
	if err := defaultProbeOrigin(context.Background(), addr, "example.com"); err != nil {
		t.Fatalf("probe against local TLS listener: %v", err)
	}
	if err := defaultProbeOrigin(context.Background(), "127.0.0.1:1", ""); !errors.Is(err, ErrOriginUnreachable) {
		t.Fatalf("closed port err = %v", err)
	}
}

// tlsListener starts a local TLS server with a throwaway certificate so the
// probe can be exercised without external network access.
func tlsListener(t *testing.T) net.Listener {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "example.com"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, &tmpl, &tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	ln, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{
		Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}},
	})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				_ = conn.(*tls.Conn).Handshake()
			}()
		}
	}()
	return ln
}
