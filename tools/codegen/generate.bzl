load("@org_pubref_rules_protobuf//protobuf:rules.bzl", "proto_compile")
load("@org_pubref_rules_protobuf//gogo:rules.bzl", "gogoslick_proto_library", "gogo_proto_library")
load("@io_bazel_rules_go//go:def.bzl", "go_library")

def _impl(ctx):
  m = []
  for k, v in ctx.attr.importmap.items():
    m += ["-m %s:%s" % (k, v)]

  args = [ctx.file.src.path, "-o=" + ctx.outputs.out.path] + m
  # print(args)

  # Action to call the script.
  ctx.action(
      mnemonic="MixerGen",
      inputs=[ctx.file.src],
      outputs=[ctx.outputs.out],
      arguments=args,
      progress_message="Generating mixer go files in: %s" % ctx.outputs.out.path,
      executable=ctx.executable._gen_tool)

mixer_gen = rule(
  implementation=_impl,
  attrs={
      "src": attr.label(allow_single_file=True),
      "out": attr.output(mandatory=True),
      "importmap": attr.string_dict(),
      "_gen_tool": attr.label(executable=True, cfg="host", allow_files=True,
                                default=Label("//tools/codegen/cmd/mixgenproc"))
  },
  output_to_genfiles=True,
)

MIXER_DEPS = [
    "//tools/codegen/pkg/adapter:go_default_library",
    "//tools/codegen/pkg/template_extension:go_default_library",
    "@com_github_istio_api//:mixer/v1/config/descriptor",
]
MIXER_INPUTS = [
    "//tools/codegen/pkg/template_extension:proto",
    "@com_github_istio_api//:mixer/v1/config/descriptor_protos",
]
MIXER_IMPORT_MAP = {
    "mixer/v1/config/descriptor/value_type.proto": "istio.io/api/mixer/v1/config/descriptor",
    "tools/codegen/pkg/template_extension/TemplateExtensions.proto": "istio.io/mixer/tools/codegen/pkg/template_extension",
}
MIXER_IMPORTS = [ "external/com_github_istio_api" ]

# TODO: fill in with complete set of GOGO DEPS and IMPORT MAPPING
GOGO_DEPS = [
    "@com_github_gogo_protobuf//gogoproto:go_default_library",
    "@com_github_gogo_protobuf//types:go_default_library",
    "@com_github_gogo_protobuf//sortkeys:go_default_library",
]
GOGO_IMPORT_MAP = {
    "gogoproto/gogo.proto": "github.com/gogo/protobuf/gogoproto",
    "google/protobuf/duration.proto": "github.com/gogo/protobuf/types",
}

PROTO_IMPORTS = ["external/com_github_google_protobuf/src"]
PROTO_INPUTS = [ "@com_github_google_protobuf//:well_known_protos" ]


def mixer_proto_library(
    name,
    protos = [],
    importmap = {},
    imports = [],
    inputs = [],
    deps = [],
    verbose = 0,
    proto_compile_args = {},
    mixer_gen_args = {},
    gogoslick_args = {},
    **kwargs):

   proto_compile_args += {
     "name": name + "_proto",
     "args" : ["--include_imports", "--include_source_info"],
     "protos": protos,
     "importmap": importmap,
     "imports": imports + MIXER_IMPORTS + PROTO_IMPORTS,
     "inputs": inputs + MIXER_INPUTS + PROTO_INPUTS,
     "verbose": verbose,
   }

   # we must run proto compile, as the mixer gen depends on the args
   # for including imports and there isn't a way to pass those args
   # through the gogo_proto_* methods at the moment.
   proto_compile(**proto_compile_args)

   gogoslick_args += {
      "name": name + "_gogo_proto",
      "protos": protos,
      "deps": MIXER_DEPS + GOGO_DEPS + deps,
      "imports": imports + MIXER_IMPORTS + PROTO_IMPORTS,
      "importmap": dict(dict(MIXER_IMPORT_MAP, **GOGO_IMPORT_MAP), **importmap),
      "inputs": inputs + MIXER_INPUTS + PROTO_INPUTS,
      # "output_to_workspace": True,
      "verbose": verbose,
   }

   # we run this proto library to get the generated pb.go files to link
   # in with the mixer generated files for a go library
   gogoslick_proto_library(**gogoslick_args)

   mixer_gen_args += {
       "name" : name + "_processor",
       "src": name + "_proto.descriptor_set",
       "importmap": dict(dict(MIXER_IMPORT_MAP, **GOGO_IMPORT_MAP), **importmap),
       "out": name + "_processor.gen.go",
   }

   mixer_gen(**mixer_gen_args)

   go_library(
      name = name,
      srcs = [name + "_processor.gen.go"],
      library = ":" + name + "_gogo_proto",
      deps = deps + MIXER_DEPS)