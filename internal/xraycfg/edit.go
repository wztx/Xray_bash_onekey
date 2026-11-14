package xraycfg

import (
	"bytes"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// EditDefaults carries the install facts that the runtime config does not
// spell out: whether a managed Nginx front owns the public port and, for TLS,
// the site name used by Nginx.
type EditDefaults struct {
	Mode       string
	PublicPort int
	Domain     string
}

// EditRequest carries the operator overrides for `xray config edit`. Zero
// numbers and empty strings keep the current value, which is what makes the
// command a patch instead of a rewrite.
type EditRequest struct {
	Listen           string
	Port             int
	PublicPort       int
	Transport        string
	WSPath           string
	XHTTPPath        string
	GRPCServiceName  string
	Target           string
	ServerNames      []string
	UUID             string
	WSPort           int
	GRPCPort         int
	XHTTPPort        int
	AllowNonLoopback bool
}

// EditResult reports what the patch changed and whether the change can drop
// live client sessions.
type EditResult struct {
	Changed    []string
	Mode       string
	Transport  string
	Port       int
	PublicPort int
	Listen     string
	Disconnect bool
	NoChanges  bool
	// Diff lists the changed runtime paths, so --dry-run and the confirmation
	// prompt can show exactly what would move.
	Diff []string
}

// EditRuntime applies an EditRequest to an existing runtime config. It reads
// the live values first, regenerates through the same generator as install
// (so the share link and Nginx fragments stay consistent), and then refuses
// the result if anything outside the requested patch changed.
func EditRuntime(raw []byte, base EditDefaults, req EditRequest) (Generated, EditResult, error) {
	root, err := parseRuntime(raw)
	if err != nil {
		return Generated{}, EditResult{}, err
	}
	inbounds := asSlice(root["inbounds"])
	spec, sharedUUID, err := editSpecFromRuntime(root, base)
	if err != nil {
		return Generated{}, EditResult{}, err
	}
	if req.UUID != "" && !sharedUUID {
		return Generated{}, EditResult{}, fmt.Errorf("inbounds use different UUIDs; edit users with 'idleleo xray user add/remove'")
	}
	changed, err := applyEditRequest(&spec, base, req)
	if err != nil {
		return Generated{}, EditResult{}, err
	}
	// The running service owns the ports this patch preserves, so a bind probe
	// would report a conflict against our own listener.
	spec.SkipPortProbe = true
	g, err := Generate(spec)
	if err != nil {
		return Generated{}, EditResult{}, err
	}
	allow, err := editScopeFor(req, len(inbounds))
	if err != nil {
		return Generated{}, EditResult{}, err
	}
	diffs, err := diffRuntime(raw, g.Config)
	if err != nil {
		return Generated{}, EditResult{}, err
	}
	for _, d := range diffs {
		if !allow.permits(d) {
			return Generated{}, EditResult{}, fmt.Errorf(
				"refusing to rewrite %q: regeneration would change a field this edit did not ask for; use 'idleleo xray install --rewrite-config'", d)
		}
	}
	res := EditResult{
		Changed:    changed,
		Mode:       spec.Mode,
		Transport:  spec.Transport,
		Port:       spec.Port,
		PublicPort: spec.PublicPort,
		Listen:     spec.Listen,
		Disconnect: disconnectProne(changed),
		NoChanges:  len(changed) == 0 || len(diffs) == 0,
		Diff:       diffs,
	}
	return g, res, nil
}

func disconnectProne(changed []string) bool {
	for _, field := range changed {
		switch field {
		case "port", "public-port", "transport", "uuid", "listen":
			return true
		}
	}
	return false
}

// editScope limits the regeneration diff to the fields the operator asked
// for. Structural transport/path edits may reshuffle the whole inbound list;
// scalar edits may only touch their own leaf.
type editScope struct {
	structural bool
	exact      map[string]bool
	prefixes   []string
}

func editScopeFor(req EditRequest, inbounds int) (editScope, error) {
	a := editScope{exact: map[string]bool{}}
	if req.Transport != "" || req.WSPath != "" || req.XHTTPPath != "" || req.GRPCServiceName != "" {
		a.structural = true
		// The generated routing rules reference inbound tags, so a transport
		// change legitimately rewrites routing.rules[*].inboundTag.
		a.prefixes = append(a.prefixes, "routing.rules")
		return a, nil
	}
	if req.Port != 0 {
		a.exact["inbounds[0].port"] = true
	}
	if req.Listen != "" {
		for i := 0; i < inbounds; i++ {
			a.exact[fmt.Sprintf("inbounds[%d].listen", i)] = true
		}
	}
	if req.UUID != "" {
		for i := 0; i < inbounds; i++ {
			a.exact[fmt.Sprintf("inbounds[%d].settings.clients[0].id", i)] = true
			// Generate normalises an empty email to the template default, so a
			// UUID edit may also materialise it. Nothing else may change.
			a.exact[fmt.Sprintf("inbounds[%d].settings.clients[0].email", i)] = true
		}
	}
	if req.Target != "" {
		a.prefixes = append(a.prefixes, "inbounds[0].streamSettings.realitySettings.target")
	}
	if len(req.ServerNames) > 0 {
		a.prefixes = append(a.prefixes, "inbounds[0].streamSettings.realitySettings.serverNames")
	}
	return a, nil
}

func (a editScope) permits(path string) bool {
	if a.structural && strings.HasPrefix(path, "inbounds") {
		return true
	}
	if a.exact[path] {
		return true
	}
	for _, p := range a.prefixes {
		if strings.HasPrefix(path, p) {
			return true
		}
	}
	return false
}

// applyEditRequest folds the overrides into the extracted spec and rejects
// combinations that would silently change unrelated topology.
func applyEditRequest(spec *Spec, base EditDefaults, req EditRequest) ([]string, error) {
	changed := []string{}
	nginxFront := base.Mode == ModeRealityNginx || base.Mode == ModeTLS
	reality := base.Mode == ModeReality || base.Mode == ModeRealityNginx
	usesWS := spec.Transport == TransportWS || spec.Transport == TransportMulti ||
		(reality && spec.Transport == TransportWS)
	usesXHTTP := spec.Transport == TransportXHTTP || spec.Transport == TransportMulti
	usesGRPC := spec.Transport == TransportGRPC || spec.Transport == TransportMulti
	if req.Transport != "" {
		spec.Transport = req.Transport
		changed = append(changed, "transport")
		usesWS = spec.Transport == TransportWS || spec.Transport == TransportMulti
		usesXHTTP = spec.Transport == TransportXHTTP || spec.Transport == TransportMulti
		usesGRPC = spec.Transport == TransportGRPC || spec.Transport == TransportMulti
	}
	if req.Listen != "" {
		if nginxFront {
			return nil, fmt.Errorf("--listen is owned by Nginx in mode %s; change the proxy or use --rewrite-config", base.Mode)
		}
		spec.Listen = req.Listen
		changed = append(changed, "listen")
	}
	if req.Port != 0 {
		spec.Port = req.Port
		if nginxFront {
			// Both Nginx-fronted modes treat --port as the public listen port.
			spec.PublicPort = req.Port
		}
		changed = append(changed, "port")
	}
	if req.PublicPort != 0 {
		spec.PublicPort = req.PublicPort
		if base.Mode == ModeRealityNginx {
			spec.Port = req.PublicPort
		}
		changed = append(changed, "public-port")
	}
	if req.WSPath != "" {
		if !usesWS {
			return nil, fmt.Errorf("--ws-path requires a transport with ws")
		}
		if req.XHTTPPath != "" {
			return nil, fmt.Errorf("specify only one of --ws-path and --xhttp-path")
		}
		spec.Path = req.WSPath
		changed = append(changed, "ws-path")
	}
	if req.XHTTPPath != "" {
		if !usesXHTTP {
			return nil, fmt.Errorf("--xhttp-path requires a transport with xhttp")
		}
		if spec.Transport == TransportMulti {
			return nil, fmt.Errorf("the multi transport fixes the xhttp path; use a single xhttp transport to change it")
		}
		spec.Path = req.XHTTPPath
		changed = append(changed, "xhttp-path")
	}
	if req.GRPCServiceName != "" {
		if !usesGRPC {
			return nil, fmt.Errorf("--grpc-service-name requires a transport with grpc")
		}
		spec.ServiceName = req.GRPCServiceName
		changed = append(changed, "grpc-service-name")
	}
	if req.Target != "" {
		if !reality {
			return nil, fmt.Errorf("--target only applies to Reality modes")
		}
		spec.Target = req.Target
		changed = append(changed, "target")
	}
	if len(req.ServerNames) > 0 {
		if !reality {
			return nil, fmt.Errorf("--server-names only applies to Reality modes")
		}
		spec.ServerNames = req.ServerNames
		changed = append(changed, "server-names")
	}
	if req.UUID != "" {
		spec.UUID = req.UUID
		changed = append(changed, "uuid")
	}
	if req.WSPort != 0 {
		if !usesWS {
			return nil, fmt.Errorf("--ws-port requires a transport with ws")
		}
		spec.WSPort = req.WSPort
		changed = append(changed, "ws-port")
	}
	if req.GRPCPort != 0 {
		if !usesGRPC {
			return nil, fmt.Errorf("--grpc-port requires a transport with grpc")
		}
		spec.GRPCPort = req.GRPCPort
		changed = append(changed, "grpc-port")
	}
	if req.XHTTPPort != 0 {
		if !usesXHTTP {
			return nil, fmt.Errorf("--xhttp-port requires a transport with xhttp")
		}
		spec.XHTTPPort = req.XHTTPPort
		changed = append(changed, "xhttp-port")
	}
	if req.AllowNonLoopback {
		spec.AllowNonLoopback = true
	}
	return changed, nil
}

// editSpecFromRuntime extracts the values Generate needs from a live config.
// It returns sharedUUID=false when the inbounds disagree on the client id,
// because a single regeneration would then rewrite every user.
func editSpecFromRuntime(root map[string]any, base EditDefaults) (Spec, bool, error) {
	inbounds := asSlice(root["inbounds"])
	if len(inbounds) == 0 {
		return Spec{}, false, fmt.Errorf("runtime config has no inbounds")
	}
	first := asMap(inbounds[0])
	spec := Spec{
		Mode:        base.Mode,
		Port:        asInt(first["port"]),
		Listen:      asString(first["listen"]),
		PublicPort:  base.PublicPort,
		Domain:      base.Domain,
		Path:        defaultPath,
		ServiceName: defaultGRPCService,
	}
	if base.Mode == ModeTLS {
		// TLS keeps Xray on a pool port; the public port lives in Nginx.
		spec.Port = base.PublicPort
	}
	networks := make([]string, 0, len(inbounds))
	var uuid, email, flow, wsPath, xhttpPath string
	sharedUUID := true
	for i, item := range inbounds {
		inbound := asMap(item)
		stream := asMap(inbound["streamSettings"])
		network := asString(stream["network"])
		if network == "" {
			network = TransportRaw
		}
		networks = append(networks, network)
		switch network {
		case TransportWS:
			if p := asString(asMap(stream["wsSettings"])["path"]); p != "" {
				wsPath = p
			}
			if i > 0 || spec.Mode == ModeTLS {
				// TLS keeps its primary ws inbound on a pool port.
				spec.WSPort = asInt(inbound["port"])
			}
		case TransportGRPC:
			if s := asString(asMap(stream["grpcSettings"])["serviceName"]); s != "" {
				spec.ServiceName = s
			}
			if i > 0 || spec.Mode == ModeTLS || spec.Mode == ModeNone {
				spec.GRPCPort = asInt(inbound["port"])
			}
		case TransportXHTTP:
			if p := asString(asMap(stream["xhttpSettings"])["path"]); p != "" {
				xhttpPath = p
			}
			if i > 0 || spec.Mode == ModeTLS || spec.Mode == ModeNone {
				spec.XHTTPPort = asInt(inbound["port"])
			}
		}
		clients := asSlice(asMap(inbound["settings"])["clients"])
		if len(clients) > 0 {
			c := asMap(clients[0])
			id := asString(c["id"])
			if i == 0 {
				uuid, email, flow = id, asString(c["email"]), asString(c["flow"])
			} else if id != uuid {
				sharedUUID = false
			}
		}
	}
	var err error
	spec.Transport, err = transportFromNetworks(spec.Mode, networks)
	if err != nil {
		return Spec{}, false, err
	}
	if wsPath != "" {
		spec.Path = wsPath
	} else if xhttpPath != "" && spec.Transport != TransportMulti {
		spec.Path = xhttpPath
	}
	spec.UUID = uuid
	spec.Email = email
	spec.Flow = flow
	firstStream := asMap(first["streamSettings"])
	switch asString(firstStream["security"]) {
	case "reality":
		rs := asMap(firstStream["realitySettings"])
		spec.Target = asString(rs["target"])
		if spec.Target == "" {
			spec.Target = asString(rs["dest"])
		}
		spec.PrivateKey = asString(rs["privateKey"])
		if ids := asSlice(rs["shortIds"]); len(ids) > 0 {
			spec.ShortID = asString(ids[0])
		}
		for _, sn := range asSlice(rs["serverNames"]) {
			spec.ServerNames = append(spec.ServerNames, asString(sn))
		}
	case "tls":
		// Direct TLS (no managed front) is not one of the supported install
		// modes; regenerating it would change the certificate wiring.
		return Spec{}, false, fmt.Errorf("direct TLS configs are not editable; reinstall with --mode tls")
	}
	if base.Mode == ModeRealityNginx || base.Mode == ModeTLS {
		spec.Port = base.PublicPort
	}
	if spec.Mode == ModeRealityBalance {
		return Spec{}, false, fmt.Errorf("reality-balance installs are not editable yet")
	}
	return spec, sharedUUID, nil
}

// transportFromNetworks maps the inbound network list back to the transport
// value used by the wizard and the generator.
func transportFromNetworks(mode string, networks []string) (string, error) {
	seen := make([]string, 0, len(networks))
	for _, n := range networks {
		found := false
		for _, s := range seen {
			if s == n {
				found = true
			}
		}
		if !found {
			seen = append(seen, n)
		}
	}
	reality := mode == ModeReality || mode == ModeRealityNginx
	others := seen
	if reality {
		others = nil
		for _, n := range seen {
			if n != TransportRaw {
				others = append(others, n)
			}
		}
		if len(others) == 0 {
			return TransportRaw, nil
		}
	}
	switch len(others) {
	case 1:
		return others[0], nil
	case 3:
		return TransportMulti, nil
	default:
		return "", fmt.Errorf("unsupported inbound network combination %v", seen)
	}
}

func parseRuntime(raw []byte) (map[string]any, error) {
	var root map[string]any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&root); err != nil {
		return nil, fmt.Errorf("runtime config is not valid JSON: %w", err)
	}
	if root == nil {
		return nil, fmt.Errorf("runtime config must be a JSON object")
	}
	return root, nil
}

// diffRuntime lists every leaf that differs between two configs, using paths
// such as inbounds[0].port so the allowance check can decide precisely.
func diffRuntime(oldRaw, newRaw []byte) ([]string, error) {
	oldRoot, err := parseRuntime(oldRaw)
	if err != nil {
		return nil, err
	}
	newRoot, err := parseRuntime(newRaw)
	if err != nil {
		return nil, err
	}
	var out []string
	diffValue("", oldRoot, newRoot, &out)
	sort.Strings(out)
	return out, nil
}

func diffValue(path string, a, b any, out *[]string) {
	am, aOK := a.(map[string]any)
	bm, bOK := b.(map[string]any)
	if aOK && bOK {
		keys := map[string]bool{}
		for k := range am {
			keys[k] = true
		}
		for k := range bm {
			keys[k] = true
		}
		names := make([]string, 0, len(keys))
		for k := range keys {
			names = append(names, k)
		}
		sort.Strings(names)
		for _, k := range names {
			diffValue(joinPath(path, k), am[k], bm[k], out)
		}
		return
	}
	as, aOK := a.([]any)
	bs, bOK := b.([]any)
	if aOK && bOK {
		if len(as) != len(bs) {
			*out = append(*out, path)
			return
		}
		for i := range as {
			diffValue(fmt.Sprintf("%s[%d]", path, i), as[i], bs[i], out)
		}
		return
	}
	if !scalarEqual(a, b) {
		*out = append(*out, path)
	}
}

func joinPath(path, key string) string {
	if path == "" {
		return key
	}
	return path + "." + key
}

func scalarEqual(a, b any) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	an, aNum := a.(json.Number)
	bn, bNum := b.(json.Number)
	if aNum && bNum {
		return an.String() == bn.String()
	}
	return fmt.Sprintf("%v", a) == fmt.Sprintf("%v", b)
}

func asMap(v any) map[string]any {
	m, _ := v.(map[string]any)
	if m == nil {
		return map[string]any{}
	}
	return m
}

func asSlice(v any) []any {
	s, _ := v.([]any)
	return s
}

func asString(v any) string {
	s, _ := v.(string)
	return s
}

func asInt(v any) int {
	switch t := v.(type) {
	case json.Number:
		i, _ := t.Int64()
		return int(i)
	case float64:
		return int(t)
	case int:
		return t
	default:
		return 0
	}
}
