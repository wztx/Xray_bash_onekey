package cli

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/hello-yunshu/Xray_bash_onekey/internal/change"
	"github.com/hello-yunshu/Xray_bash_onekey/internal/deploy"
	"github.com/hello-yunshu/Xray_bash_onekey/internal/xraycfg"
)

// editFail keeps an unreachable Reality origin in the "refused, nothing
// written" class (exit 2) instead of a generic execution failure.
func editFail(opts Options, cfg config, err error) int {
	if errors.Is(err, deploy.ErrOriginUnreachable) {
		return fail(opts, cfg, &change.UsageError{Msg: err.Error()})
	}
	return fail(opts, cfg, err)
}

// xrayConfig owns `xray config ...`. Editing is a patch, not a rewrite: the
// generator keeps every value the operator did not name.
func xrayConfig(ctx context.Context, opts Options, cfg config, args []string) int {
	if len(args) == 0 || args[0] != "edit" {
		return usage(opts, cfg.lang, "help")
	}
	return xrayConfigEdit(ctx, opts, cfg, args[1:])
}

func xrayConfigEdit(ctx context.Context, opts Options, cfg config, args []string) int {
	if hasFlag(args, "--rewrite-config") {
		return fail(opts, cfg, &change.UsageError{
			Msg: "xray config edit patches in place; use 'idleleo xray install --rewrite-config' for a full rewrite",
		})
	}
	if flagValue(args, "--relay-target") != "" || flagValue(args, "--relay-listen-port") != "" {
		return xrayConfigEditRelay(ctx, opts, cfg, args)
	}
	req, err := editRequestFromFlags(args)
	if err != nil {
		return fail(opts, cfg, &change.UsageError{Msg: err.Error()})
	}
	dryRun := hasFlag(args, "--dry-run")
	spec := deploy.EditSpec{
		Root:                 cfg.root,
		ConfigPath:           flagValue(args, "--path"),
		Request:              req,
		NoRestart:            hasFlag(args, "--no-restart"),
		NoProbe:              hasFlag(args, "--no-probe"),
		DryRun:               true,
		AllowContainerWrites: hasFlag(args, "--container"),
	}
	preview, err := deploy.EditConfig(ctx, spec)
	if err != nil {
		return editFail(opts, cfg, err)
	}
	cfg.json = cfg.json || hasFlag(args, "--json")
	if preview.NoChanges {
		if cfg.json {
			return writeJSON(opts, preview)
		}
		fmt.Fprintln(opts.Out, "no changes: the requested values already match the runtime config")
		return 0
	}
	if !dryRun && preview.Disconnect && !hasFlag(args, "--yes") {
		if !opts.TTY {
			return fail(opts, cfg, &change.UsageError{
				Msg: "this edit changes " + strings.Join(preview.Changed, ", ") +
					" and will drop live connections; re-run with --yes to confirm",
			})
		}
		fmt.Fprintf(opts.Out, "This edit changes %s and will drop live client sessions.\n", strings.Join(preview.Changed, ", "))
		if !confirmEdit(opts) {
			fmt.Fprintln(opts.Out, "aborted; nothing was changed")
			return 1
		}
	}
	if dryRun {
		if cfg.json {
			return writeJSON(opts, preview)
		}
		printEditPreview(opts, preview)
		return 0
	}
	spec.DryRun = false
	report, err := deploy.EditConfig(ctx, spec)
	if err != nil {
		return editFail(opts, cfg, err)
	}
	if cfg.json {
		return writeJSON(opts, report)
	}
	printEditReport(opts, report)
	return 0
}

func xrayConfigEditRelay(ctx context.Context, opts Options, cfg config, args []string) int {
	port := 0
	if raw := flagValue(args, "--relay-listen-port"); raw != "" {
		v, err := strconv.Atoi(raw)
		if err != nil || v < 1 || v > 65535 {
			return fail(opts, cfg, &change.UsageError{Msg: "--relay-listen-port must be an integer between 1 and 65535"})
		}
		port = v
	}
	target := flagValue(args, "--relay-target")
	if target == "" && port == 0 {
		return fail(opts, cfg, &change.UsageError{Msg: "relay edit needs --relay-target and/or --relay-listen-port"})
	}
	dryRun := hasFlag(args, "--dry-run")
	spec := deploy.RelayEditSpec{
		Root:                 cfg.root,
		Target:               target,
		ListenPort:           port,
		NoRestart:            hasFlag(args, "--no-restart"),
		DryRun:               true,
		AllowContainerWrites: hasFlag(args, "--container"),
	}
	preview, err := deploy.EditRelay(ctx, spec)
	if err != nil {
		return fail(opts, cfg, err)
	}
	cfg.json = cfg.json || hasFlag(args, "--json")
	if preview.NoChanges {
		if cfg.json {
			return writeJSON(opts, preview)
		}
		fmt.Fprintln(opts.Out, "no changes: the relay already forwards to that target")
		return 0
	}
	if !dryRun && !hasFlag(args, "--yes") {
		if !opts.TTY {
			return fail(opts, cfg, &change.UsageError{
				Msg: "changing the relay target or listen port restarts the front; re-run with --yes to confirm",
			})
		}
		fmt.Fprintf(opts.Out, "This relay edit changes %s:%d and will restart the front.\n", preview.Target, preview.ListenPort)
		if !confirmEdit(opts) {
			fmt.Fprintln(opts.Out, "aborted; nothing was changed")
			return 1
		}
	}
	if dryRun {
		if cfg.json {
			return writeJSON(opts, preview)
		}
		fmt.Fprintf(opts.Out, "would relay: %s -> %s\n", relayListenLabel(preview), preview.Target)
		return 0
	}
	spec.DryRun = false
	report, err := deploy.EditRelay(ctx, spec)
	if err != nil {
		return fail(opts, cfg, err)
	}
	if cfg.json {
		return writeJSON(opts, report)
	}
	fmt.Fprintf(opts.Out, "relay: %s -> %s\n", relayListenLabel(report), report.Target)
	fmt.Fprintf(opts.Out, "nginx verified=%t\n", report.NginxVerified)
	if report.BackupDir != "" {
		fmt.Fprintf(opts.Out, "backup: %s\n", report.BackupDir)
	}
	if report.NoRestart {
		fmt.Fprintln(opts.Out, "restart: deferred (--no-restart)")
	}
	return 0
}

func relayListenLabel(r deploy.RelayEditReport) string {
	return fmt.Sprintf(":%d", r.ListenPort)
}

// editRequestFromFlags maps the CLI vocabulary onto the patch request. Every
// value is optional; omitted flags mean keep.
func editRequestFromFlags(args []string) (xraycfg.EditRequest, error) {
	req := xraycfg.EditRequest{
		Listen:           flagValue(args, "--listen"),
		Transport:        flagValue(args, "--transport"),
		WSPath:           flagValue(args, "--ws-path"),
		XHTTPPath:        flagValue(args, "--xhttp-path"),
		GRPCServiceName:  flagValue(args, "--grpc-service-name"),
		Target:           flagValue(args, "--target"),
		UUID:             flagValue(args, "--uuid"),
		Domain:           flagValue(args, "--domain"),
		CertFile:         flagValue(args, "--cert"),
		KeyFile:          flagValue(args, "--cert-key"),
		AllowNonLoopback: hasFlag(args, "--allow-non-loopback"),
	}
	if raw := flagValue(args, "--server-names"); raw != "" {
		for _, name := range strings.Split(raw, ",") {
			if name = strings.TrimSpace(name); name != "" {
				req.ServerNames = append(req.ServerNames, name)
			}
		}
	}
	for _, port := range []struct {
		flag string
		dst  *int
	}{
		{"--port", &req.Port},
		{"--public-port", &req.PublicPort},
		{"--ws-port", &req.WSPort},
		{"--grpc-port", &req.GRPCPort},
		{"--xhttp-port", &req.XHTTPPort},
	} {
		raw := flagValue(args, port.flag)
		if raw == "" {
			continue
		}
		v, err := strconv.Atoi(raw)
		if err != nil || v < 1 || v > 65535 {
			return xraycfg.EditRequest{}, fmt.Errorf("%s must be an integer between 1 and 65535", port.flag)
		}
		*port.dst = v
	}
	if req.Listen == "" && req.Transport == "" && req.WSPath == "" && req.XHTTPPath == "" &&
		req.GRPCServiceName == "" && req.Target == "" && len(req.ServerNames) == 0 && req.UUID == "" &&
		req.Domain == "" && req.CertFile == "" && req.KeyFile == "" &&
		req.Port == 0 && req.PublicPort == 0 && req.WSPort == 0 && req.GRPCPort == 0 && req.XHTTPPort == 0 {
		return xraycfg.EditRequest{}, fmt.Errorf("nothing to edit: pass at least one of --listen, --port, --public-port, --transport, --ws-path, --xhttp-path, --grpc-service-name, --target, --server-names, --uuid, --domain, --cert, --cert-key")
	}
	return req, nil
}

func confirmEdit(opts Options) bool {
	fmt.Fprint(opts.Out, "Continue? [y/N]: ")
	scanner := bufio.NewScanner(opts.In)
	if !scanner.Scan() {
		return false
	}
	answer := strings.ToLower(strings.TrimSpace(scanner.Text()))
	return answer == "y" || answer == "yes"
}

func printEditPreview(opts Options, preview deploy.EditReport) {
	fmt.Fprintf(opts.Out, "mode=%s transport=%s\n", preview.Mode, preview.Transport)
	fmt.Fprintf(opts.Out, "changed=%s\n", strings.Join(preview.Changed, ","))
	for _, d := range preview.Diff {
		fmt.Fprintf(opts.Out, "diff=%s\n", d)
	}
	printTLSReport(opts, preview)
	fmt.Fprintf(opts.Out, "config: %s sha256=%s -> %s\n", preview.ConfigPath, preview.OldSHA256, preview.NewSHA256)
	if preview.OriginProbe != "" {
		fmt.Fprintf(opts.Out, "origin: %s ok\n", preview.OriginProbe)
	}
	fmt.Fprintln(opts.Out, "dry-run: nothing was written")
}

// printTLSReport surfaces the front-owned TLS values and the handshake
// verdict. "skipped" is never printed as a pass.
func printTLSReport(opts Options, r deploy.EditReport) {
	if r.Domain == "" && r.CertFile == "" {
		return
	}
	fmt.Fprintf(opts.Out, "tls: domain=%s cert=%s key=%s\n", r.Domain, r.CertFile, r.CertKeyFile)
	if r.CertNotAfter != "" {
		fmt.Fprintf(opts.Out, "cert: notAfter=%s sans=%s\n", r.CertNotAfter, strings.Join(r.CertSANs, ","))
	}
	if r.TLSProbe != "" {
		if r.TLSServerName == "" {
			fmt.Fprintf(opts.Out, "tls-probe: %s\n", r.TLSProbe)
		} else {
			fmt.Fprintf(opts.Out, "tls-probe: %s sni=%s version=%s systemTrusted=%t\n",
				r.TLSProbe, r.TLSServerName, r.TLSVersion, r.TLSTrusted)
		}
	}
	if r.ScheduleUpdated {
		fmt.Fprintf(opts.Out, "schedule: cert-renew target updated (%s)\n", r.SchedulePath)
	}
}

func printEditReport(opts Options, report deploy.EditReport) {
	fmt.Fprintf(opts.Out, "mode=%s transport=%s\n", report.Mode, report.Transport)
	fmt.Fprintf(opts.Out, "changed=%s\n", strings.Join(report.Changed, ","))
	for _, d := range report.Diff {
		fmt.Fprintf(opts.Out, "diff=%s\n", d)
	}
	printTLSReport(opts, report)
	fmt.Fprintf(opts.Out, "config: %s sha256=%s\n", report.ConfigPath, report.NewSHA256)
	if report.OriginProbe != "" {
		fmt.Fprintf(opts.Out, "origin: %s ok\n", report.OriginProbe)
	}
	if report.NginxUpdated {
		fmt.Fprintf(opts.Out, "nginx: updated verified=%t\n", report.NginxVerified)
	}
	if report.ShareURI != "" {
		fmt.Fprintf(opts.Out, "share: %s\n", report.ShareURI)
	}
	if report.BackupDir != "" {
		fmt.Fprintf(opts.Out, "backup: %s\n", report.BackupDir)
	}
	if report.NoRestart {
		fmt.Fprintln(opts.Out, "restart: deferred (--no-restart)")
	}
	for _, w := range report.Warnings {
		fmt.Fprintf(opts.Out, "warning=%s\n", w)
	}
}
