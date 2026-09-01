// Self-check for the client's "did we reach the middleware?" decision.
// Compiles the REAL source file, so it fails if the logic breaks:
//   xcrun swiftc -o /tmp/diag_check BeNeM/Models/Diagnostics.swift scripts/check_diagnostics_logic.swift && /tmp/diag_check
@main
struct DiagnosticsLogicCheck {
    static func main() {
        // The middleware app itself answered.
        assert(DiagnosticsResult.reachedMiddleware(statusCode: 200))
        assert(DiagnosticsResult.reachedMiddleware(statusCode: 204))
        // Caddy answering for a dead middleware app container is NOT the middleware.
        assert(!DiagnosticsResult.reachedMiddleware(statusCode: 502))
        assert(!DiagnosticsResult.reachedMiddleware(statusCode: 503))
        assert(!DiagnosticsResult.reachedMiddleware(statusCode: 504))
        // Any non-2xx means the middleware did not answer as itself.
        assert(!DiagnosticsResult.reachedMiddleware(statusCode: 401))
        print("check_diagnostics_logic: OK")
    }
}
