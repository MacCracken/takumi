use criterion::{Criterion, black_box, criterion_group, criterion_main};
use std::path::PathBuf;
use takumi::{
    BuildRecipe, BuildSteps, DependencySpec, HardeningFlag, PackageMetadata, SecurityFlags,
    SourceSpec, TakumiBuildSystem,
};
use tempfile::TempDir;

// ---------------------------------------------------------------------------
// Recipe parsing benchmarks
// ---------------------------------------------------------------------------

const MINIMAL_RECIPE: &str = r#"
[package]
name = "hello"
version = "1.0.0"
description = "Hello world"
license = "MIT"

[source]
url = "https://example.com/hello-1.0.0.tar.gz"
sha256 = "abc123def456"

[depends]

[build]
make = "make"
"#;

const FULL_RECIPE: &str = r#"
[package]
name = "openssl"
version = "3.5.2"
description = "TLS/SSL cryptographic library"
license = "Apache-2.0"
groups = ["base", "crypto"]
release = 3
arch = "x86_64"

[source]
url = "https://www.openssl.org/source/openssl-3.5.2.tar.gz"
sha256 = "e1f5c1c2b3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0"
patches = ["fix-musl.patch", "agnos-paths.patch"]

[depends]
runtime = ["glibc", "zlib"]
build = ["perl", "make"]

[build]
pre_build = "sed -i 's/foo/bar/' Makefile.in"
configure = "./config --prefix=/usr --openssldir=/etc/ssl shared"
make = "make -j$(nproc)"
check = "make test"
install = "make DESTDIR=$PKG install"
post_install = "rm -rf $PKG/usr/share/doc"

[security]
hardening = ["pie", "relro", "fortify", "stackprotector"]
cflags = "-O2"
ldflags = "-Wl,--as-needed"
"#;

fn bench_parse_minimal(c: &mut Criterion) {
    c.bench_function("parse_minimal_recipe", |b| {
        b.iter(|| toml::from_str::<BuildRecipe>(black_box(MINIMAL_RECIPE)).unwrap())
    });
}

fn bench_parse_full(c: &mut Criterion) {
    c.bench_function("parse_full_recipe", |b| {
        b.iter(|| toml::from_str::<BuildRecipe>(black_box(FULL_RECIPE)).unwrap())
    });
}

// ---------------------------------------------------------------------------
// Validation benchmarks
// ---------------------------------------------------------------------------

fn make_valid_recipe() -> BuildRecipe {
    BuildRecipe {
        package: PackageMetadata {
            name: "bench-pkg".to_string(),
            version: "1.0.0".to_string(),
            description: "Benchmark package".to_string(),
            license: "MIT".to_string(),
            groups: vec!["base".to_string()],
            release: 1,
            arch: Some("x86_64".to_string()),
        },
        source: SourceSpec {
            url: "https://example.com/bench-1.0.0.tar.gz".to_string(),
            sha256: "e1f5c1c2b3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0".to_string(),
            patches: vec![],
        },
        depends: DependencySpec {
            runtime: vec!["glibc".to_string()],
            build: vec!["gcc".to_string()],
        },
        build: BuildSteps {
            configure: Some("./configure".to_string()),
            make: Some("make".to_string()),
            check: None,
            install: Some("make install".to_string()),
            pre_build: None,
            post_install: None,
        },
        security: SecurityFlags {
            hardening: vec![
                HardeningFlag::Pie,
                HardeningFlag::Relro,
                HardeningFlag::Fortify,
                HardeningFlag::StackProtector,
            ],
            cflags: None,
            ldflags: None,
        },
    }
}

fn bench_validate_recipe(c: &mut Criterion) {
    let recipe = make_valid_recipe();
    c.bench_function("validate_recipe", |b| {
        b.iter(|| TakumiBuildSystem::validate_recipe(black_box(&recipe)).unwrap())
    });
}

// ---------------------------------------------------------------------------
// Flag generation benchmarks
// ---------------------------------------------------------------------------

fn bench_generate_cflags(c: &mut Criterion) {
    let flags = SecurityFlags {
        hardening: vec![
            HardeningFlag::Pie,
            HardeningFlag::Fortify,
            HardeningFlag::StackProtector,
        ],
        cflags: Some("-O2 -march=x86-64".to_string()),
        ldflags: None,
    };
    c.bench_function("generate_cflags", |b| {
        b.iter(|| TakumiBuildSystem::generate_cflags(black_box(&flags)))
    });
}

fn bench_generate_ldflags(c: &mut Criterion) {
    let flags = SecurityFlags {
        hardening: vec![
            HardeningFlag::Pie,
            HardeningFlag::FullRelro,
            HardeningFlag::Relro,
            HardeningFlag::Bindnow,
        ],
        cflags: None,
        ldflags: Some("-Wl,--as-needed".to_string()),
    };
    c.bench_function("generate_ldflags_with_dedup", |b| {
        b.iter(|| TakumiBuildSystem::generate_ldflags(black_box(&flags)))
    });
}

// ---------------------------------------------------------------------------
// Build order resolution benchmarks
// ---------------------------------------------------------------------------

fn build_system_with_chain(n: usize) -> (TakumiBuildSystem, Vec<String>) {
    let mut sys = TakumiBuildSystem::new(
        PathBuf::from("/tmp/recipes"),
        PathBuf::from("/tmp/build"),
        PathBuf::from("/tmp/output"),
    );
    let mut names = Vec::with_capacity(n);
    for i in 0..n {
        let name = format!("pkg-{i:04}");
        let build_deps: Vec<String> = if i > 0 {
            vec![format!("pkg-{:04}", i - 1)]
        } else {
            vec![]
        };
        let deps_toml = format!(
            "[{}]",
            build_deps
                .iter()
                .map(|d| format!("\"{d}\""))
                .collect::<Vec<_>>()
                .join(", ")
        );
        let toml_str = format!(
            r#"
[package]
name = "{name}"
version = "1.0"
description = "test"
license = "MIT"

[source]
url = "https://example.com/{name}.tar.gz"
sha256 = "abc"

[depends]
build = {deps_toml}

[build]
make = "make"
"#
        );
        let recipe: BuildRecipe = toml::from_str(&toml_str).unwrap();
        names.push(name.clone());
        sys.loaded_recipes_mut().insert(name, recipe);
    }
    (sys, names)
}

fn bench_resolve_build_order_10(c: &mut Criterion) {
    let (sys, names) = build_system_with_chain(10);
    c.bench_function("resolve_build_order_10", |b| {
        b.iter(|| sys.resolve_build_order(black_box(&names)).unwrap())
    });
}

fn bench_resolve_build_order_100(c: &mut Criterion) {
    let (sys, names) = build_system_with_chain(100);
    c.bench_function("resolve_build_order_100", |b| {
        b.iter(|| sys.resolve_build_order(black_box(&names)).unwrap())
    });
}

fn bench_resolve_build_order_300(c: &mut Criterion) {
    let (sys, names) = build_system_with_chain(300);
    c.bench_function("resolve_build_order_300", |b| {
        b.iter(|| sys.resolve_build_order(black_box(&names)).unwrap())
    });
}

// ---------------------------------------------------------------------------
// File list creation benchmark
// ---------------------------------------------------------------------------

fn bench_create_file_list(c: &mut Criterion) {
    let tmp = TempDir::new().unwrap();
    // Create a realistic fake-root with nested directories and files
    let dirs = ["usr/bin", "usr/lib", "usr/share/doc", "etc/conf.d"];
    for d in &dirs {
        std::fs::create_dir_all(tmp.path().join(d)).unwrap();
    }
    for i in 0..20 {
        let path = tmp.path().join(format!("usr/lib/libfoo{i}.so"));
        std::fs::write(&path, format!("lib content {i}")).unwrap();
    }
    for i in 0..5 {
        let path = tmp.path().join(format!("usr/bin/tool{i}"));
        std::fs::write(&path, format!("binary content {i}")).unwrap();
    }
    std::fs::write(tmp.path().join("etc/conf.d/app.conf"), "key=value").unwrap();

    c.bench_function("create_file_list_26_files", |b| {
        b.iter(|| TakumiBuildSystem::create_file_list(black_box(tmp.path())).unwrap())
    });
}

// ---------------------------------------------------------------------------
// SHA-256 hashing benchmark
// ---------------------------------------------------------------------------

fn bench_sha256_1kb(c: &mut Criterion) {
    let data = vec![0xABu8; 1024];
    c.bench_function("sha256_1kb", |b| {
        b.iter(|| {
            use sha2::{Digest, Sha256};
            let mut h = Sha256::new();
            h.update(black_box(&data));
            let _ = h.finalize();
        })
    });
}

fn bench_sha256_1mb(c: &mut Criterion) {
    let data = vec![0xABu8; 1024 * 1024];
    c.bench_function("sha256_1mb", |b| {
        b.iter(|| {
            use sha2::{Digest, Sha256};
            let mut h = Sha256::new();
            h.update(black_box(&data));
            let _ = h.finalize();
        })
    });
}

// ---------------------------------------------------------------------------
// Serde roundtrip benchmarks
// ---------------------------------------------------------------------------

fn bench_manifest_roundtrip(c: &mut Criterion) {
    let manifest = takumi::ArkManifest {
        name: "bench-pkg".to_string(),
        version: "1.0.0".to_string(),
        release: 1,
        description: "Benchmark package".to_string(),
        arch: "x86_64".to_string(),
        size_installed: 1_048_576,
        build_date: chrono::Utc::now(),
        builder: "takumi/0.1.0".to_string(),
        source_url: "https://example.com/bench-1.0.0.tar.gz".to_string(),
        source_hash: "abcdef1234567890".to_string(),
        license: "MIT".to_string(),
        groups: vec!["base".to_string()],
        depends: vec!["glibc".to_string(), "zlib".to_string()],
    };
    c.bench_function("manifest_json_roundtrip", |b| {
        b.iter(|| {
            let json = serde_json::to_string(black_box(&manifest)).unwrap();
            let _: takumi::ArkManifest = serde_json::from_str(&json).unwrap();
        })
    });
}

criterion_group!(
    benches,
    bench_parse_minimal,
    bench_parse_full,
    bench_validate_recipe,
    bench_generate_cflags,
    bench_generate_ldflags,
    bench_resolve_build_order_10,
    bench_resolve_build_order_100,
    bench_resolve_build_order_300,
    bench_create_file_list,
    bench_sha256_1kb,
    bench_sha256_1mb,
    bench_manifest_roundtrip,
);
criterion_main!(benches);
