use std::collections::BTreeMap;
use std::fs;

use serde::Serialize;
use serde_json;
use sha2::{Digest, Sha256};
use syn::{self, File, Item};

// ------------------------------------------------------------------
// Helpers: whitespace-stripping to make hashing formatting-agnostic
// ------------------------------------------------------------------
fn strip_ws(s: &str) -> String {
    s.split_whitespace().collect()
}

// ------------------------------------------------------------------
// Stripped-down AST skeleton representation for semantic hashing
// ------------------------------------------------------------------

#[derive(Serialize, Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct StructDef {
    name: String,
    generics: String,
    fields: BTreeMap<String, String>,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct EnumDef {
    name: String,
    generics: String,
    variants: BTreeMap<String, Vec<String>>,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct FnSig {
    name: String,
    generics: String,
    params: Vec<String>,
    ret: String,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct TraitDef {
    name: String,
    generics: String,
    items: Vec<String>,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct ImplBlock {
    trait_name: Option<String>,
    for_type: String,
    generics: String,
    items: Vec<String>,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct ModuleSkeleton {
    structs: Vec<StructDef>,
    enums: Vec<EnumDef>,
    functions: Vec<FnSig>,
    traits: Vec<TraitDef>,
    impls: Vec<ImplBlock>,
    type_aliases: BTreeMap<String, String>,
    constants: BTreeMap<String, String>,
}

fn type_to_string(ty: &syn::Type) -> String {
    strip_ws(&quote::quote!(#ty).to_string())
}

fn generics_to_string(gen: &syn::Generics) -> String {
    if gen.params.is_empty() {
        String::new()
    } else {
        strip_ws(&quote::quote!(#gen).to_string())
    }
}

fn build_skeleton(file: &File) -> ModuleSkeleton {
    let mut sk = ModuleSkeleton {
        structs: Vec::new(),
        enums: Vec::new(),
        functions: Vec::new(),
        traits: Vec::new(),
        impls: Vec::new(),
        type_aliases: BTreeMap::new(),
        constants: BTreeMap::new(),
    };

    for item in &file.items {
        match item {
            Item::Struct(s) => {
                let mut fields = BTreeMap::new();
                match &s.fields {
                    syn::Fields::Named(n) => {
                        for f in &n.named {
                            let name = f.ident.as_ref().unwrap().to_string();
                            fields.insert(name, type_to_string(&f.ty));
                        }
                    }
                    syn::Fields::Unnamed(u) => {
                        for (i, f) in u.unnamed.iter().enumerate() {
                            fields.insert(format!("f{}", i), type_to_string(&f.ty));
                        }
                    }
                    syn::Fields::Unit => {}
                }
                sk.structs.push(StructDef {
                    name: s.ident.to_string(),
                    generics: generics_to_string(&s.generics),
                    fields,
                });
            }
            Item::Enum(e) => {
                let mut variants = BTreeMap::new();
                for v in &e.variants {
                    let mut fields = Vec::new();
                    match &v.fields {
                        syn::Fields::Named(n) => {
                            for f in &n.named {
                                fields.push(type_to_string(&f.ty));
                            }
                        }
                        syn::Fields::Unnamed(u) => {
                            for f in &u.unnamed {
                                fields.push(type_to_string(&f.ty));
                            }
                        }
                        syn::Fields::Unit => {}
                    }
                    variants.insert(v.ident.to_string(), fields);
                }
                sk.enums.push(EnumDef {
                    name: e.ident.to_string(),
                    generics: generics_to_string(&e.generics),
                    variants,
                });
            }
            Item::Fn(f) => {
                let params: Vec<String> = f.sig.inputs.iter().map(|arg| {
                    strip_ws(&quote::quote!(#arg).to_string())
                }).collect();
                let ret = match &f.sig.output {
                    syn::ReturnType::Default => "()".to_string(),
                    syn::ReturnType::Type(_, ty) => type_to_string(ty),
                };
                sk.functions.push(FnSig {
                    name: f.sig.ident.to_string(),
                    generics: generics_to_string(&f.sig.generics),
                    params,
                    ret,
                });
            }
            Item::Trait(t) => {
                let items: Vec<String> = t.items.iter().map(|it| {
                    strip_ws(&quote::quote!(#it).to_string())
                }).collect();
                sk.traits.push(TraitDef {
                    name: t.ident.to_string(),
                    generics: generics_to_string(&t.generics),
                    items,
                });
            }
            Item::Impl(i) => {
                let trait_name = i.trait_.as_ref().map(|(_bang, path, _for)| {
                    strip_ws(&quote::quote!(#path).to_string())
                });
                let for_type = type_to_string(&i.self_ty);
                let items: Vec<String> = i.items.iter().map(|it| {
                    strip_ws(&quote::quote!(#it).to_string())
                }).collect();
                sk.impls.push(ImplBlock {
                    trait_name,
                    for_type,
                    generics: generics_to_string(&i.generics),
                    items,
                });
            }
            Item::Type(ty) => {
                sk.type_aliases.insert(ty.ident.to_string(), type_to_string(&ty.ty));
            }
            Item::Const(c) => {
                sk.constants.insert(
                    c.ident.to_string(),
                    strip_ws(&quote::quote!(#c.expr).to_string()),
                );
            }
            _ => {}
        }
    }

    sk
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: {} <path/to/lib.rs>", args[0]);
        std::process::exit(1);
    }

    let source = fs::read_to_string(&args[1]).expect("Failed to read source file");
    let ast: File = syn::parse_file(&source).expect("Failed to parse Rust source");

    let skeleton = build_skeleton(&ast);
    let json = serde_json::to_string(&skeleton).expect("Failed to serialize skeleton");

    let mut hasher = Sha256::new();
    hasher.update(json.as_bytes());
    let hash = format!("{:x}", hasher.finalize());

    println!("{}", hash);
}
