package xraycfg

import (
	"encoding/json"
	"strings"
	"testing"
)

func editBase(t *testing.T) []byte {
	t.Helper()
	stubCanBind(t, func(string, int) bool { return true })
	g, err := Generate(Spec{Mode: ModeReality, Domain: "example.com", Transport: TransportWS})
	if err != nil {
		t.Fatal(err)
	}
	return g.Config
}

func editInbounds(t *testing.T, raw []byte) []map[string]any {
	t.Helper()
	root, err := parseRuntime(raw)
	if err != nil {
		t.Fatal(err)
	}
	out := []map[string]any{}
	for _, in := range asSlice(root["inbounds"]) {
		out = append(out, asMap(in))
	}
	return out
}

func TestEditUUIDKeepsEveryOtherValue(t *testing.T) {
	raw := editBase(t)
	before := editInbounds(t, raw)
	g, res, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{UUID: "11111111-2222-3333-4444-555555555555"})
	if err != nil {
		t.Fatal(err)
	}
	if res.NoChanges || !res.Disconnect {
		t.Fatalf("uuid edit must report a disconnect-prone change: %+v", res)
	}
	after := editInbounds(t, g.Config)
	if len(after) != len(before) {
		t.Fatalf("inbound count changed: %d -> %d", len(before), len(after))
	}
	for i := range before {
		if asInt(before[i]["port"]) != asInt(after[i]["port"]) {
			t.Fatalf("inbound %d port drifted: %v -> %v", i, before[i]["port"], after[i]["port"])
		}
		if asString(before[i]["listen"]) != asString(after[i]["listen"]) {
			t.Fatalf("inbound %d listen drifted", i)
		}
		bs := asMap(before[i]["streamSettings"])
		as := asMap(after[i]["streamSettings"])
		if asString(asMap(bs["realitySettings"])["privateKey"]) != asString(asMap(as["realitySettings"])["privateKey"]) {
			t.Fatalf("inbound %d reality key drifted", i)
		}
		if asString(asMap(bs["wsSettings"])["path"]) != asString(asMap(as["wsSettings"])["path"]) {
			t.Fatalf("inbound %d ws path drifted", i)
		}
	}
	client := asMap(asSlice(asMap(after[0]["settings"])["clients"])[0])
	if asString(client["id"]) != "11111111-2222-3333-4444-555555555555" {
		t.Fatalf("uuid not applied: %v", client["id"])
	}
	if !strings.Contains(g.ShareURI, "11111111-2222-3333-4444-555555555555") {
		t.Fatalf("share link not regenerated: %s", g.ShareURI)
	}
}

func TestEditPortOnlyTouchesPort(t *testing.T) {
	raw := editBase(t)
	g, res, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443}, EditRequest{Port: 8080})
	if err != nil {
		t.Fatal(err)
	}
	if !res.Disconnect {
		t.Fatalf("port edit must be marked disconnect-prone")
	}
	if got := asInt(editInbounds(t, g.Config)[0]["port"]); got != 8080 {
		t.Fatalf("port = %d, want 8080", got)
	}
}

func TestEditTransportRebuildsInbounds(t *testing.T) {
	raw := editBase(t)
	g, res, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{Transport: TransportGRPC})
	if err != nil {
		t.Fatal(err)
	}
	if res.Transport != TransportGRPC || !res.Disconnect {
		t.Fatalf("transport edit result = %+v", res)
	}
	in := editInbounds(t, g.Config)
	if len(in) != 2 {
		t.Fatalf("reality+grpc must keep the raw inbound and add grpc, got %d", len(in))
	}
	if got := asString(asMap(asMap(in[1]["streamSettings"])["grpcSettings"])["serviceName"]); got == "" {
		t.Fatalf("grpc inbound lost its service name")
	}
	// The Reality identity must survive a transport change.
	oldClient := asMap(asSlice(asMap(editInbounds(t, raw)[0]["settings"])["clients"])[0])
	newClient := asMap(asSlice(asMap(in[0]["settings"])["clients"])[0])
	if asString(oldClient["id"]) != asString(newClient["id"]) {
		t.Fatalf("transport edit changed the UUID")
	}
}

func TestEditTargetAndServerNames(t *testing.T) {
	raw := editBase(t)
	g, _, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{Target: "www.example.org:443", ServerNames: []string{"www.example.org"}})
	if err != nil {
		t.Fatal(err)
	}
	rs := asMap(asMap(editInbounds(t, g.Config)[0]["streamSettings"])["realitySettings"])
	if asString(rs["target"]) != "www.example.org:443" {
		t.Fatalf("target = %v", rs["target"])
	}
	names := asSlice(rs["serverNames"])
	if len(names) != 1 || asString(names[0]) != "www.example.org" {
		t.Fatalf("serverNames = %v", rs["serverNames"])
	}
}

func TestEditRefusesUnknownTopLevelChanges(t *testing.T) {
	raw := editBase(t)
	root, err := parseRuntime(raw)
	if err != nil {
		t.Fatal(err)
	}
	root["custom-tag"] = "keep-me"
	patched, err := json.Marshal(root)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := EditRuntime(patched, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{Port: 8080}); err == nil || !strings.Contains(err.Error(), "custom-tag") {
		t.Fatalf("unknown top-level field must block the edit, got %v", err)
	}
}

func TestEditRefusesMultiUserUUID(t *testing.T) {
	raw := editBase(t)
	root, _ := parseRuntime(raw)
	in := asMap(asSlice(root["inbounds"])[0])
	settings := asMap(in["settings"])
	clients := asSlice(settings["clients"])
	clone, _ := json.Marshal(clients[0])
	var second map[string]any
	if err := json.Unmarshal(clone, &second); err != nil {
		t.Fatal(err)
	}
	second["id"] = "99999999-2222-3333-4444-555555555555"
	settings["clients"] = append(clients, second)
	patched, _ := json.Marshal(root)
	if _, _, err := EditRuntime(patched, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{UUID: "11111111-2222-3333-4444-555555555555"}); err == nil {
		t.Fatalf("a single-uuid regeneration must not silently drop extra users")
	}
}

func TestEditMultiUserUUIDPointsAtUserCommand(t *testing.T) {
	raw := editBase(t)
	root, _ := parseRuntime(raw)
	in := asMap(asSlice(root["inbounds"])[0])
	settings := asMap(in["settings"])
	clients := asSlice(settings["clients"])
	primaryEmail := asString(asMap(clients[0])["email"])
	clone, _ := json.Marshal(clients[0])
	var second map[string]any
	if err := json.Unmarshal(clone, &second); err != nil {
		t.Fatal(err)
	}
	second["id"] = "99999999-2222-3333-4444-555555555555"
	second["email"] = "user-b@idleleo"
	settings["clients"] = append(clients, second)
	patched, _ := json.Marshal(root)
	_, _, err := EditRuntime(patched, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{UUID: "11111111-2222-3333-4444-555555555555"})
	if err == nil {
		t.Fatal("multi-user config must refuse a global uuid rewrite")
	}
	// The message must be actionable, not a vague pointer to another command.
	for _, want := range []string{"idleleo xray user uuid --email " + primaryEmail,
		"--new-uuid 11111111-2222-3333-4444-555555555555", "would drop them"} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("error %q missing %q", err, want)
		}
	}
}

func TestEditRejectsFrontOwnedFields(t *testing.T) {
	raw := editBase(t)
	if _, _, err := EditRuntime(raw, EditDefaults{Mode: ModeRealityNginx, PublicPort: 443},
		EditRequest{Listen: "127.0.0.1"}); err == nil || !strings.Contains(err.Error(), "--listen") {
		t.Fatalf("nginx-front listen edit must be rejected, got %v", err)
	}
	if _, _, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{Target: "example.com:443"}); err != nil {
		// reality target is legal; only non-reality must fail
		t.Fatal(err)
	}
	spec := Spec{Mode: ModeTLS, Transport: TransportWS}
	if _, err := applyEditRequest(&spec, EditDefaults{Mode: ModeTLS}, EditRequest{Target: "example.com:443"}); err == nil ||
		!strings.Contains(err.Error(), "Reality") {
		t.Fatalf("target edit outside reality must be rejected, got %v", err)
	}
}

func TestEditNoOpWhenNothingRequested(t *testing.T) {
	raw := editBase(t)
	g, res, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443}, EditRequest{})
	if err != nil {
		t.Fatal(err)
	}
	if !res.NoChanges {
		t.Fatalf("empty request must be a no-op: %+v", res)
	}
	before, _ := parseRuntime(raw)
	after, _ := parseRuntime(g.Config)
	if b, _ := json.Marshal(before); string(b) != string(mustMarshal(after)) {
		t.Fatalf("no-op edit rewrote the config")
	}
}

func mustMarshal(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

func editTLSBase(t *testing.T) ([]byte, EditDefaults) {
	t.Helper()
	stubCanBind(t, func(string, int) bool { return true })
	g, err := Generate(Spec{
		Mode: ModeTLS, Transport: TransportWS, Domain: "example.com",
		Port: 10080, WSPort: 10080, PublicPort: 8443,
	})
	if err != nil {
		t.Fatal(err)
	}
	return g.Config, EditDefaults{
		Mode: ModeTLS, PublicPort: 8443, Domain: "example.com",
		CertFile: DefaultCertFile, KeyFile: DefaultKeyFile,
	}
}

func TestEditTLSDomainRewritesNginxWithoutRuntimeDiff(t *testing.T) {
	raw, base := editTLSBase(t)
	g, res, err := EditRuntime(raw, base, EditRequest{Domain: "new.example.com"})
	if err != nil {
		t.Fatal(err)
	}
	if res.NoChanges {
		t.Fatalf("a domain edit must not be reported as no-op: %+v", res)
	}
	if res.Domain != "new.example.com" {
		t.Fatalf("domain = %q", res.Domain)
	}
	if len(res.Diff) != 0 {
		t.Fatalf("the TLS domain is front-owned; runtime diff = %v", res.Diff)
	}
	if !strings.Contains(g.NginxConf, "server_name           new.example.com;") {
		t.Fatalf("nginx server_name not rewritten:\n%s", g.NginxConf)
	}
	if !strings.Contains(g.NginxConf, DefaultCertFile) || !strings.Contains(g.NginxConf, DefaultKeyFile) {
		t.Fatal("a domain edit must keep the configured certificate pair")
	}
	if diff, err := diffRuntime(raw, g.Config); err != nil || len(diff) != 0 {
		t.Fatalf("runtime config changed: diff=%v err=%v", diff, err)
	}
}

func TestEditTLSCertificatePairIsAFrontOwnedChange(t *testing.T) {
	raw, base := editTLSBase(t)
	g, res, err := EditRuntime(raw, base, EditRequest{
		CertFile: "/etc/idleleo/cert/example.com.crt", KeyFile: "/etc/idleleo/cert/example.com.key",
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.NoChanges {
		t.Fatalf("a certificate edit must rewrite Nginx: %+v", res)
	}
	if !strings.Contains(g.NginxConf, "ssl_certificate       /etc/idleleo/cert/example.com.crt;") {
		t.Fatalf("certificate path not applied:\n%s", g.NginxConf)
	}
	if !strings.Contains(g.NginxConf, "ssl_certificate_key   /etc/idleleo/cert/example.com.key;") {
		t.Fatalf("key path not applied:\n%s", g.NginxConf)
	}
	if res.CertFile != "/etc/idleleo/cert/example.com.crt" || res.KeyFile != "/etc/idleleo/cert/example.com.key" {
		t.Fatalf("effective pair = %q %q", res.CertFile, res.KeyFile)
	}
}

func TestEditTLSNoOpWhenValuesMatch(t *testing.T) {
	raw, base := editTLSBase(t)
	_, res, err := EditRuntime(raw, base, EditRequest{Domain: "example.com", CertFile: DefaultCertFile})
	if err != nil {
		t.Fatal(err)
	}
	if !res.NoChanges {
		t.Fatalf("repeating the live values must be a no-op: %+v", res)
	}
}

func TestEditRejectsTLSOwnedFieldsOutsideTLSMode(t *testing.T) {
	raw := editBase(t)
	if _, _, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{Domain: "example.com"}); err == nil || !strings.Contains(err.Error(), "TLS") {
		t.Fatalf("reality must reject --domain, got %v", err)
	}
	if _, _, err := EditRuntime(raw, EditDefaults{Mode: ModeReality, PublicPort: 443},
		EditRequest{CertFile: "/tmp/a.crt"}); err == nil || !strings.Contains(err.Error(), "TLS") {
		t.Fatalf("reality must reject --cert, got %v", err)
	}
}
