-- xmake.lua for agbcc (GBA C Compiler)
-- Build with MinGW on Windows

set_project("agbcc")
set_version("1.0.0")

-- Set minimum xmake version
set_xmakever("2.7.0")

-- Add build modes
add_rules("mode.debug", "mode.release")

-- Default to release mode
set_defaultmode("release")

-- Common settings
set_languages("gnu11")
set_warnings("none")  -- Old GCC code has many warnings

-- Disable warnings that old GCC code triggers
add_cxflags(
    "-Wno-incompatible-pointer-types",
    "-Wno-pointer-sign",
    "-Wno-format-overflow",
    "-Wno-maybe-uninitialized",
    "-Wno-unused-but-set-variable",
    "-Wno-unused-variable",
    "-Wno-pointer-to-int-cast",
    "-Wno-int-to-pointer-cast",
    {force = true}
)

-- Platform-specific settings
if is_plat("windows", "mingw") then
    add_defines("_WIN32")
end

-- ============================================================================
-- Code generators (gen* tools) - built first to generate source files
-- ============================================================================

local gen_common_sources = {
    "gcc/rtl.c",
    "gcc/bitmap.c", 
    "gcc/obstack.c",
    "gcc/print-rtl.c"
}

-- gengenrtl - generates genrtl.h and genrtl.c
target("gengenrtl")
    set_kind("binary")
    set_default(false)
    add_files("gcc/gengenrtl.c")
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- gencheck - generates tree-check.h
target("gencheck")
    set_kind("binary")
    set_default(false)
    add_files("gcc/gencheck.c")
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genconfig - generates insn-config.h
target("genconfig")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genconfig.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genflags - generates insn-flags.h
target("genflags")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genflags.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- gencodes - generates insn-codes.h
target("gencodes")
    set_kind("binary")
    set_default(false)
    add_files("gcc/gencodes.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genemit - generates insn-emit.c
target("genemit")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genemit.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genrecog - generates insn-recog.c
target("genrecog")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genrecog.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genopinit - generates insn-opinit.c
target("genopinit")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genopinit.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genextract - generates insn-extract.c
target("genextract")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genextract.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genpeep - generates insn-peep.c
target("genpeep")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genpeep.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genattr - generates insn-attr.h
target("genattr")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genattr.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genattrtab - generates insn-attrtab.c
target("genattrtab")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genattrtab.c", "gcc/rtlanal.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- genoutput - generates insn-output.c
target("genoutput")
    set_kind("binary")
    set_default(false)
    add_files("gcc/genoutput.c", table.unpack(gen_common_sources))
    add_includedirs("gcc")
    set_targetdir("$(builddir)/generators")

-- ============================================================================
-- Rule to generate files from machine description
-- ============================================================================

rule("generate_insn_files")
    set_extensions(".md")
    on_build(function (target)
        import("core.project.depend")
        import("core.project.project")
        
        local gcc_dir = path.join(os.projectdir(), "gcc")
        local md_file = path.join(gcc_dir, "thumb.md")
        local gen_dir = path.join(os.projectdir(), "build", "generators")
        
        -- Ensure generators directory exists
        os.mkdir(gen_dir)
        
        local function run_generator(gen_name, output_file, extra_args)
            local gen_path = path.join(gen_dir, gen_name .. (is_plat("windows") and ".exe" or ""))
            if os.isfile(gen_path) then
                local output_path = path.join(gcc_dir, output_file)
                local args = extra_args or {}
                if gen_name == "gengenrtl" then
                    -- gengenrtl takes two output files as arguments
                    os.execv(gen_path, {path.join(gcc_dir, "genrtl.h"), path.join(gcc_dir, "genrtl.c")})
                elseif gen_name == "gencheck" then
                    local result = os.iorunv(gen_path)
                    io.writefile(output_path, result)
                else
                    local result = os.iorunv(gen_path, {md_file})
                    io.writefile(output_path, result)
                end
                print("Generated: " .. output_file)
            end
        end
        
        -- Will be called from custom build script
    end)

-- ============================================================================
-- Main agbcc compiler target
-- ============================================================================

target("agbcc")
    set_kind("binary")
    set_default(true)
    
    add_includedirs("gcc")
    
    -- Main source files
    add_files(
        "gcc/toplev.c",
        "gcc/version.c",
        "gcc/tree.c",
        "gcc/print-tree.c",
        "gcc/stor-layout.c",
        "gcc/fold-const.c",
        "gcc/function.c",
        "gcc/stmt.c",
        "gcc/except.c",
        "gcc/expr.c",
        "gcc/calls.c",
        "gcc/expmed.c",
        "gcc/explow.c",
        "gcc/optabs.c",
        "gcc/varasm.c",
        "gcc/emit-rtl.c",
        "gcc/real.c",
        "gcc/regmove.c",
        "gcc/dwarf2out.c",
        "gcc/alias.c",
        "gcc/integrate.c",
        "gcc/jump.c",
        "gcc/cse.c",
        "gcc/loop.c",
        "gcc/unroll.c",
        "gcc/flow.c",
        "gcc/stupid.c",
        "gcc/combine.c",
        "gcc/varray.c",
        "gcc/regclass.c",
        "gcc/local-alloc.c",
        "gcc/global.c",
        "gcc/reload.c",
        "gcc/reload1.c",
        "gcc/caller-save.c",
        "gcc/gcse.c",
        "gcc/final.c",
        "gcc/recog.c",
        "gcc/lcm.c",
        "gcc/thumb.c",
        "gcc/getpwd.c",
        "gcc/convert.c",
        "gcc/dyn-string.c",
        "gcc/splay-tree.c",
        "gcc/graph.c",
        "gcc/sbitmap.c",
        "gcc/resource.c",
        "gcc/c-parse.c",
        "gcc/c-lex.c",
        "gcc/c-decl.c",
        "gcc/c-typeck.c",
        "gcc/c-convert.c",
        "gcc/c-aux-info.c",
        "gcc/c-common.c",
        "gcc/c-iterate.c",
        -- RTL and support files
        "gcc/rtl.c",
        "gcc/bitmap.c",
        "gcc/obstack.c",
        "gcc/rtlanal.c",
        "gcc/print-rtl.c"
    )
    
    -- Generated files (will be added after generation)
    add_files(
        "gcc/genrtl.c",
        "gcc/insn-peep.c",
        "gcc/insn-opinit.c",
        "gcc/insn-recog.c",
        "gcc/insn-extract.c",
        "gcc/insn-output.c",
        "gcc/insn-emit.c",
        "gcc/insn-attrtab.c"
    )
    
    set_targetdir("$(projectdir)")

-- ============================================================================
-- Old agbcc compiler (used to build libgcc)
-- ============================================================================

target("old_agbcc")
    set_kind("binary")
    set_default(true)
    
    add_includedirs("gcc")
    add_defines("OLD_COMPILER")
    
    -- Same source files as agbcc
    add_files(
        "gcc/toplev.c",
        "gcc/version.c",
        "gcc/tree.c",
        "gcc/print-tree.c",
        "gcc/stor-layout.c",
        "gcc/fold-const.c",
        "gcc/function.c",
        "gcc/stmt.c",
        "gcc/except.c",
        "gcc/expr.c",
        "gcc/calls.c",
        "gcc/expmed.c",
        "gcc/explow.c",
        "gcc/optabs.c",
        "gcc/varasm.c",
        "gcc/emit-rtl.c",
        "gcc/real.c",
        "gcc/regmove.c",
        "gcc/dwarf2out.c",
        "gcc/alias.c",
        "gcc/integrate.c",
        "gcc/jump.c",
        "gcc/cse.c",
        "gcc/loop.c",
        "gcc/unroll.c",
        "gcc/flow.c",
        "gcc/stupid.c",
        "gcc/combine.c",
        "gcc/varray.c",
        "gcc/regclass.c",
        "gcc/local-alloc.c",
        "gcc/global.c",
        "gcc/reload.c",
        "gcc/reload1.c",
        "gcc/caller-save.c",
        "gcc/gcse.c",
        "gcc/final.c",
        "gcc/recog.c",
        "gcc/lcm.c",
        "gcc/thumb.c",
        "gcc/getpwd.c",
        "gcc/convert.c",
        "gcc/dyn-string.c",
        "gcc/splay-tree.c",
        "gcc/graph.c",
        "gcc/sbitmap.c",
        "gcc/resource.c",
        "gcc/c-parse.c",
        "gcc/c-lex.c",
        "gcc/c-decl.c",
        "gcc/c-typeck.c",
        "gcc/c-convert.c",
        "gcc/c-aux-info.c",
        "gcc/c-common.c",
        "gcc/c-iterate.c",
        "gcc/rtl.c",
        "gcc/bitmap.c",
        "gcc/obstack.c",
        "gcc/rtlanal.c",
        "gcc/print-rtl.c",
        "gcc/genrtl.c",
        "gcc/insn-peep.c",
        "gcc/insn-opinit.c",
        "gcc/insn-recog.c",
        "gcc/insn-extract.c",
        "gcc/insn-output.c",
        "gcc/insn-emit.c",
        "gcc/insn-attrtab.c"
    )
    
    set_targetdir("$(projectdir)")

-- ============================================================================
-- Custom task to generate source files before building
-- ============================================================================

task("generate")
    set_category("build")
    set_menu {
        usage = "xmake generate",
        description = "Generate source files from machine description",
        options = {}
    }
    on_run(function ()
        import("core.project.project")
        import("core.base.option")
        
        local gcc_dir = path.join(os.projectdir(), "gcc")
        local gen_dir = path.join(os.projectdir(), "build", "generators")
        local md_file = path.join(gcc_dir, "thumb.md")
        
        os.mkdir(gen_dir)
        
        -- Build generators first
        local generators = {
            "gengenrtl", "gencheck", "genconfig", "genflags", "gencodes",
            "genemit", "genrecog", "genopinit", "genextract", "genpeep",
            "genattr", "genattrtab", "genoutput"
        }
        
        print("Building code generators...")
        for _, gen in ipairs(generators) do
            os.exec("xmake build " .. gen)
        end
        
        local exe_suffix = is_plat("windows") and ".exe" or ""
        
        -- Generate files
        print("Generating source files...")
        
        -- gengenrtl -> genrtl.h, genrtl.c
        local gengenrtl = path.join(gen_dir, "gengenrtl" .. exe_suffix)
        if os.isfile(gengenrtl) then
            os.execv(gengenrtl, {
                path.join(gcc_dir, "genrtl.h"),
                path.join(gcc_dir, "genrtl.c")
            })
            print("Generated: genrtl.h, genrtl.c")
        end
        
        -- gencheck -> tree-check.h
        local gencheck = path.join(gen_dir, "gencheck" .. exe_suffix)
        if os.isfile(gencheck) then
            local result = os.iorunv(gencheck)
            io.writefile(path.join(gcc_dir, "tree-check.h"), result)
            print("Generated: tree-check.h")
        end
        
        -- Generators that take thumb.md as input
        local md_generators = {
            {name = "genconfig", output = "insn-config.h"},
            {name = "genflags", output = "insn-flags.h"},
            {name = "gencodes", output = "insn-codes.h"},
            {name = "genemit", output = "insn-emit.c"},
            {name = "genrecog", output = "insn-recog.c"},
            {name = "genopinit", output = "insn-opinit.c"},
            {name = "genextract", output = "insn-extract.c"},
            {name = "genpeep", output = "insn-peep.c"},
            {name = "genattr", output = "insn-attr.h"},
            {name = "genattrtab", output = "insn-attrtab.c"},
            {name = "genoutput", output = "insn-output.c"},
        }
        
        for _, gen in ipairs(md_generators) do
            local gen_path = path.join(gen_dir, gen.name .. exe_suffix)
            if os.isfile(gen_path) then
                local result = os.iorunv(gen_path, {md_file})
                io.writefile(path.join(gcc_dir, gen.output), result)
                print("Generated: " .. gen.output)
            end
        end
        
        print("Generation complete!")
    end)

-- ============================================================================
-- Build all task
-- ============================================================================

task("buildall")
    set_category("build")
    set_menu {
        usage = "xmake buildall",
        description = "Generate files and build agbcc and old_agbcc",
        options = {}
    }
    on_run(function ()
        os.exec("xmake generate")
        os.exec("xmake build agbcc")
        os.exec("xmake build old_agbcc")
        print("Build complete! agbcc and old_agbcc are ready.")
    end)
