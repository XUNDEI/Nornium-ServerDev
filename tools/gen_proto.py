"""Regenerate readable .proto files from the compiled FileDescriptorSet (proto.pb)."""
import os
import sys
from google.protobuf import descriptor_pb2

SRC = os.path.join(os.path.dirname(__file__), "..", "reference", "proto.pb")
DST = os.path.join(os.path.dirname(__file__), "..", "reference", "proto")

TYPE_MAP = {
    1: "double", 2: "float", 3: "int64", 4: "uint64", 5: "int32",
    6: "fixed64", 7: "fixed32", 8: "bool", 9: "string", 10: "group",
    11: "message", 12: "bytes", 13: "uint32", 14: "enum", 15: "sfixed32",
    16: "sfixed64", 17: "sint32", 18: "sint64",
}


def field_type(f):
    if f.type in (11, 14) and f.type_name:
        return f.type_name.lstrip(".")
    return TYPE_MAP.get(f.type, "unknown")


def label(f):
    # FieldDescriptorProto.Label: LABEL_OPTIONAL=1, LABEL_REQUIRED=2, LABEL_REPEATED=3.
    # The descriptor set is proto3: singular fields carry no label keyword.
    return {1: "", 2: "required ", 3: "repeated "}.get(f.label, "")


def enum_default(f, enums):
    if f.type == 14 and f.default_value and not f.default_value.isdigit():
        return " = %s [%default = %s]" % (f.number, f.default_value)
    return " = %d" % f.number


def dump_message(m, enums, indent=1):
    pad = "  " * indent
    lines = []
    if m.enum_type:
        for e in m.enum_type:
            lines.append(dump_enum(e, indent))
    for e in m.nested_type:
        lines.append(dump_message(e, enums, indent))
    oneof_groups = {}
    plain_fields = []
    for f in m.field:
        if f.HasField("oneof_index"):
            oneof_groups.setdefault(f.oneof_index, []).append(f)
        else:
            plain_fields.append(f)
    for f in plain_fields:
        default = ""
        if f.default_value:
            default = " [default = %s]" % f.default_value
        lines.append("%s%s%s %s = %d%s;" % (pad, label(f), field_type(f), f.name, f.number, default))
    for idx, fields in oneof_groups.items():
        name = m.oneof_decl[idx].name if idx < len(m.oneof_decl) else "oneof_%d" % idx
        lines.append("%soneof %s {" % (pad, name))
        for f in fields:
            lines.append("%s  %s %s = %d;" % (pad, field_type(f), f.name, f.number))
        lines.append("%s}" % pad)
    return lines


def dump_enum(e, indent=1):
    pad = "  " * indent
    lines = ["%senum %s {" % (pad[:-2], e.name)]
    for v in e.value:
        lines.append("%s  %s = %d;" % (pad, v.name, v.number))
    lines.append("%s}" % pad[:-2])
    return "\n".join(lines)


def main():
    fds = descriptor_pb2.FileDescriptorSet()
    with open(SRC, "rb") as fh:
        fds.ParseFromString(fh.read())
    os.makedirs(DST, exist_ok=True)
    total_msgs = 0
    for fd in fds.file:
        out = []
        out.append("// Reconstructed from proto.pb (Nornium/GHS client %s)" % fd.name)
        out.append('syntax = "proto3";')
        if fd.package:
            out.append("package %s;" % fd.package)
        for dep in fd.dependency:
            out.append('import "%s";' % dep)
        out.append("")
        for e in fd.enum_type:
            out.append(dump_enum(e, 0))
            out.append("")
        for m in fd.message_type:
            total_msgs += 1
            out.append("message %s {" % m.name)
            out.extend(dump_message(m, fd.enum_type))
            out.append("}")
            out.append("")
        path = os.path.join(DST, fd.name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(out))
        print("wrote", fd.name)
    print("total messages:", total_msgs)


if __name__ == "__main__":
    main()
