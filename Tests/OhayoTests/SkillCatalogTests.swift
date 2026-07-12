import XCTest
@testable import Ohayo

final class SkillCatalogTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Cria `<dir>/<nome>/SKILL.md` (ou só a pasta, com `withFile: false`).
    private func makeSkill(at dir: URL, named name: String, withFile: Bool = true) throws {
        let skillDir = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        if withFile {
            try "---\nname: \(name)\n---\n".write(
                to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
    }

    func testClaudeListaSkillsPessoaisOrdenadas() throws {
        let skills = root.appendingPathComponent("skills")
        try makeSkill(at: skills, named: "zeta")
        try makeSkill(at: skills, named: "alfa")
        XCTAssertEqual(SkillCatalog.skills(for: .claude, at: root),
                       [SkillRef(name: "alfa"), SkillRef(name: "zeta")])
    }

    func testClaudeIncluiSkillsDePluginsComNamespace() throws {
        let versionDir = root.appendingPathComponent(
            "plugins/cache/claude-plugins-official/superpowers/6.1.1/skills")
        try makeSkill(at: versionDir, named: "brainstorming")
        XCTAssertEqual(SkillCatalog.skills(for: .claude, at: root),
                       [SkillRef(name: "superpowers:brainstorming")])
    }

    func testVersoesMultiplasDoMesmoPluginDeduplicam() throws {
        let cache = root.appendingPathComponent("plugins/cache/mp/plug")
        try makeSkill(at: cache.appendingPathComponent("1.0.0/skills"), named: "x")
        try makeSkill(at: cache.appendingPathComponent("2.0.0/skills"), named: "x")
        XCTAssertEqual(SkillCatalog.skills(for: .claude, at: root),
                       [SkillRef(name: "plug:x")])
    }

    func testPastaSemSkillMdEhIgnorada() throws {
        try makeSkill(at: root.appendingPathComponent("skills"), named: "vazia", withFile: false)
        XCTAssertEqual(SkillCatalog.skills(for: .claude, at: root), [])
    }

    func testCodexListaSkillsEIgnoraDotSystem() throws {
        let skills = root.appendingPathComponent("skills")
        try makeSkill(at: skills, named: "gmud")
        try makeSkill(at: skills, named: ".system")
        XCTAssertEqual(SkillCatalog.skills(for: .codex, at: root),
                       [SkillRef(name: "gmud")])
    }

    func testCodexNaoVarrePlugins() throws {
        let versionDir = root.appendingPathComponent("plugins/cache/mp/plug/1.0.0/skills")
        try makeSkill(at: versionDir, named: "x")
        XCTAssertEqual(SkillCatalog.skills(for: .codex, at: root), [])
    }

    func testDiretorioInexistenteRetornaVazio() {
        let missing = root.appendingPathComponent("nao-existe")
        XCTAssertEqual(SkillCatalog.skills(for: .claude, at: missing), [])
        XCTAssertEqual(SkillCatalog.skills(for: .codex, at: missing), [])
    }
}
