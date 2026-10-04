import Base
# I64DIV gate header. Every def under test is reached THROUGH H, i.e. through the
# real tinybendygrad/helpers.bend. This file defines NO i64 arithmetic of its own,
# so a mutation of helpers.bend moves these rows.
import ./../../../tinybendygrad/helpers.bend as H
