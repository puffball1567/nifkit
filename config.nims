# Shared build settings.
# ARC keeps the codec runtime small and predictable for C ABI consumers.
# The implementation avoids reference cycles; cross-structure links should use
# ids or indexes rather than owning back-references.
switch("mm", "arc")
switch("path", "src")
