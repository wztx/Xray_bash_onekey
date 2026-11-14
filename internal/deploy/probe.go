package deploy

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"strconv"
	"time"

	"github.com/hello-yunshu/Xray_bash_onekey/internal/xraycfg"
)

// ErrOriginUnreachable marks a Reality origin probe failure. The edit path
// treats it as a refusal: nothing is written.
var ErrOriginUnreachable = errors.New("origin unreachable")

// probeOrigin is a seam so tests can exercise the edit flow without network.
var probeOrigin = defaultProbeOrigin

const (
	probeDialTimeout = 5 * time.Second
	probeTLSTimeout  = 5 * time.Second
)

// defaultProbeOrigin checks that the Reality target accepts a TCP connection
// and, when an SNI is supplied on a TLS port, completes a TLS handshake. It
// does not verify the certificate chain: Reality only needs a live TLS origin.
func defaultProbeOrigin(ctx context.Context, target, sni string) error {
	host, port, err := net.SplitHostPort(target)
	if err != nil {
		host, port = target, "443"
	}
	if host == "" {
		return fmt.Errorf("%w: target %q has no host", ErrOriginUnreachable, target)
	}
	addr := net.JoinHostPort(host, port)
	dialer := net.Dialer{Timeout: probeDialTimeout}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return fmt.Errorf("%w: tcp connect to %s failed: %v", ErrOriginUnreachable, addr, err)
	}
	defer conn.Close()
	if sni == "" || !tlsPort(port) {
		return nil
	}
	tlsConn := tls.Client(conn, &tls.Config{
		ServerName:         sni,
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS12,
	})
	defer tlsConn.Close()
	_ = tlsConn.SetDeadline(time.Now().Add(probeTLSTimeout))
	if err := tlsConn.HandshakeContext(ctx); err != nil {
		return fmt.Errorf("%w: tls handshake with %s (sni %s) failed: %v",
			ErrOriginUnreachable, addr, sni, err)
	}
	return nil
}

func tlsPort(port string) bool {
	n, err := strconv.Atoi(port)
	if err != nil {
		return false
	}
	return n == 443 || n == 8443
}

func probeDescription(target, sni string) string {
	host, port, err := net.SplitHostPort(target)
	if err != nil {
		host, port = target, "443"
	}
	if sni != "" && tlsPort(port) {
		return fmt.Sprintf("tcp+tls %s (sni %s)", net.JoinHostPort(host, port), sni)
	}
	return "tcp " + net.JoinHostPort(host, port)
}

// probeOriginIfRequested probes the effective Reality origin only when the
// operator asked to change --target or --server-names.
func probeOriginIfRequested(ctx context.Context, req xraycfg.EditRequest, res xraycfg.EditResult, report *EditReport) error {
	if req.Target == "" && len(req.ServerNames) == 0 {
		return nil
	}
	sni := ""
	if len(res.ServerNames) > 0 {
		sni = res.ServerNames[0]
	}
	target := res.Target
	if target == "" && sni != "" {
		target = net.JoinHostPort(sni, "443")
	}
	if target == "" {
		return nil
	}
	if err := probeOrigin(ctx, target, sni); err != nil {
		return fmt.Errorf("%w; configuration was not changed", err)
	}
	report.OriginTarget = target
	report.OriginProbe = probeDescription(target, sni)
	return nil
}
