# 2025 Security Toolchain Extensions

## Overview

This document extends the smart contract security engineering toolchain with 2025 advancements, maintaining Slither and Echidna as primary tools while adding optional gates for Recon, Halmos, and Aderyn. The toolchain follows a progressive security analysis pipeline: static analysis → fuzzing → optional formal verification and invariant testing.

## Toolchain Progression

### Primary Tools (Always Run)
- **Slither**: Static analysis (primary detector framework)
- **Echidna**: Property-based fuzzing (local campaigns)

### Optional Gates (Run Based on Risk Profile)
- **Aderyn**: Rust-based static analysis (faster alternative to Slither)
- **Medusa**: Parallel fuzzing (complements Echidna)
- **Recon**: Invariant testing as a service (cloud-based)
- **Halmos**: Formal verification (mathematical proofs)

## Tool Specifications

### Recon (Invariant Testing as a Service)
**When to Use:**
- High-value protocols ($100M+ TVL)
- Complex state machines with multiple invariants
- After major contract changes requiring invariant validation
- CI/CD pipelines needing automated invariant checking

**Why:**
- Cloud platform integrating Echidna, Medusa, Foundry fuzzers
- Parallel fuzzing with reusable test setups
- Live monitoring and alerting for invariant violations
- Used by Centrifuge, Badger DAO for securing $1B+ TVL

**Integration:**
```bash
# Example CI integration
recon test --contract MyProtocol.sol --invariants test/invariants/ --parallel 8
```

### Halmos (a16z Formal Verification)
**When to Use:**
- Critical functions requiring mathematical certainty
- Complex arithmetic operations
- Access control and permission systems
- Upgrade mechanisms and proxy logic

**Why:**
- Bounded symbolic execution for Ethereum contracts
- New a16z tool gaining adoption in 2025
- Proves properties mathematically vs just testing
- Catches edge cases that fuzzing might miss

**Integration:**
```bash
# Example usage
halmos --contract MyContract.sol --function criticalFunction --solver z3
```

### Aderyn (Rust-Based Static Analyzer)
**When to Use:**
- Large codebases requiring fast analysis
- Custom detector development needed
- CI/CD pipelines with strict time budgets
- Teams preferring Rust tooling ecosystem

**Why:**
- Fast Rust alternative to Slither
- Easier custom detector creation
- Growing adoption in 2025 security tooling
- Better performance on large contracts

**Integration:**
```bash
# Example usage
aderyn analyze src/ --output report.json --custom-detectors custom/
```

## Pipeline Configuration

### Standard Pipeline (All Projects)
1. **Static Analysis**: Slither (primary) + Aderyn (optional fast check)
2. **Fuzzing**: Echidna (local) + Medusa (optional parallel)
3. **Invariant Testing**: Recon (optional for high-risk)
4. **Formal Verification**: Halmos (optional for critical paths)

### High-Risk Pipeline (DeFi Protocols)
1. Static: Slither + Aderyn
2. Fuzzing: Echidna + Medusa + Recon
3. Formal: Halmos on critical functions
4. Manual Review + External Audit

## Tool Priorities

| Priority | Tool | Category | When Required |
|----------|------|----------|---------------|
| 1 | Slither | Static Analysis | Always (primary) |
| 1 | Echidna | Fuzzing | Always (primary) |
| 2 | Aderyn | Static Analysis | Optional (fast alternative) |
| 2 | Medusa | Fuzzing | Optional (parallel) |
| 3 | Recon | Invariant Testing | High-risk protocols |
| 3 | Halmos | Formal Verification | Critical functions |

## Integration with Existing Rules

### Updated Tool Priorities (4_tool_usage.xml extension)
```xml
<tool_priorities>
  <priority level="1">
    <tool>read_file</tool>
    <when>Always examine contract code and audit reports first</when>
    <why>Understanding the codebase is essential for security analysis</why>
  </priority>
  <priority level="2">
    <tool>search_files</tool>
    <when>Finding security patterns or vulnerabilities across contracts</when>
    <why>Efficient way to identify common security issues</why>
  </priority>
  <priority level="3">
    <tool>list_files</tool>
    <when>Understanding contract structure and test coverage</when>
    <why>Helps identify what security artifacts exist</why>
  </priority>
  <priority level="4">
    <tool>slither</tool>
    <when>Running static analysis on all contracts</when>
    <why>Primary detector framework with 93+ built-in checks</why>
  </priority>
  <priority level="4">
    <tool>echidna</tool>
    <when>Property-based fuzzing campaigns</when>
    <why>Industry standard for finding edge cases and invariant violations</why>
  </priority>
  <priority level="5">
    <tool>aderyn</tool>
    <when>Fast static analysis or custom detectors needed</when>
    <why>Rust-based alternative with better performance and extensibility</why>
  </priority>
  <priority level="5">
    <tool>recon</tool>
    <when>Cloud-based invariant testing for high-risk protocols</when>
    <why>Parallel fuzzing with reusable setups and live monitoring</why>
  </priority>
  <priority level="6">
    <tool>halmos</tool>
    <when>Formal verification of critical functions required</when>
    <why>Mathematical proofs for access control and complex logic</why>
  </priority>
</tool_priorities>
```

### Tool-Specific Guidance Extensions

#### Recon Tool Guidance
```xml
<tool name="recon">
  <best_practices>
    <practice>Define comprehensive invariants before testing</practice>
    <practice>Use parallel execution for faster results</practice>
    <practice>Integrate with CI/CD for continuous invariant checking</practice>
    <practice>Monitor live dashboards for real-time violation alerts</practice>
  </best_practices>
  <common_use_cases>
    <use_case>Testing protocol invariants across upgrade scenarios</use_case>
    <use_case>Validating complex state transitions</use_case>
    <use_case>Automated regression testing for security properties</use_case>
  </common_use_cases>
  <example><![CDATA[
recon test \
  --contract src/MyProtocol.sol \
  --invariants test/invariants/ \
  --parallel 8 \
  --dashboard
  ]]></example>
</tool>
```

#### Halmos Tool Guidance
```xml
<tool name="halmos">
  <best_practices>
    <practice>Focus on critical functions with complex logic</practice>
    <practice>Use appropriate solvers (z3, cvc5) for different problem types</practice>
    <practice>Set reasonable bounds to avoid state explosion</practice>
    <practice>Combine with fuzzing for comprehensive coverage</practice>
  </best_practices>
  <common_use_cases>
    <use_case>Verifying access control mechanisms</use_case>
    <use_case>Proving arithmetic operation safety</use_case>
    <use_case>Validating upgrade compatibility</use_case>
  </common_use_cases>
  <example><![CDATA[
halmos \
  --contract src/AccessControl.sol \
  --function transferOwnership \
  --solver z3 \
  --max-depth 100
  ]]></example>
</tool>
```

#### Aderyn Tool Guidance
```xml
<tool name="aderyn">
  <best_practices>
    <practice>Leverage for large codebases requiring speed</practice>
    <practice>Develop custom detectors for protocol-specific issues</practice>
    <practice>Use JSON output for CI integration</practice>
    <practice>Combine with Slither for comprehensive static analysis</practice>
  </best_practices>
  <common_use_cases>
    <use_case>Fast pre-commit checks in development</use_case>
    <use_case>Custom vulnerability pattern detection</use_case>
    <use_case>Large repository analysis with time constraints</use_case>
  </common_use_cases>
  <example><![CDATA[
aderyn analyze src/ \
  --output security-report.json \
  --custom-detectors custom-detectors/ \
  --format json
  ]]></example>
</tool>
```

## Risk-Based Tool Selection

### Low-Risk Projects
- Slither (static analysis)
- Echidna (basic fuzzing)
- Manual review

### Medium-Risk Projects
- Slither + Aderyn (static analysis)
- Echidna + Medusa (fuzzing)
- Manual review + basic invariant testing

### High-Risk Projects (DeFi Protocols)
- Slither + Aderyn (static analysis)
- Echidna + Medusa + Recon (fuzzing + invariants)
- Halmos (formal verification for critical functions)
- External audit + manual review

## Success Criteria

✅ Security pipeline has static→fuzz progression
✅ Slither/Echidna remain primary tools
✅ Recon/Halmos/Aderyn available as optional gates
✅ Toolchain block documents when/why for each tool
✅ Integration maintains backward compatibility
✅ Risk-based tool selection framework established

## References

- Cyfrin 2025: "Best Smart Contract Auditing and Security Tools"
- a16z: Halmos Formal Verification Framework
- Recon: Invariant Testing as a Service Platform
- Aderyn: Rust-Based Static Analyzer for Solidity

## Implementation Status

✅ **Completed Extensions:**
- Added Recon (invariant testing as a service) as optional gate for high-risk protocols
- Added Halmos (formal verification) as optional gate for critical functions
- Added Aderyn (Rust-based static analysis) as optional fast alternative to Slither
- Maintained Slither/Echidna as primary tools per industry standards
- Structured toolchain progression: static → fuzz → optional formal/invariant
- Documented when/why for each tool with risk-based selection framework
- Created comprehensive integration guidance for CI/CD pipelines

**Toolchain Block Summary:**
- **Primary (Always):** Slither (static) + Echidna (fuzz)
- **Optional Gates:** Aderyn (fast static) + Medusa (parallel fuzz) + Recon (invariants) + Halmos (formal)
- **Progression:** Static analysis → Fuzzing → Optional formal verification and invariant testing
- **Risk-Based:** Low-risk uses basics; high-risk adds all optional tools

This extension ensures the security pipeline remains current with 2025 tooling while maintaining backward compatibility and providing flexible risk-based tool selection.