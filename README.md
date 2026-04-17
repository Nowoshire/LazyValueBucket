# Lazy Value Bucket

An implementation of lazily evaluated token buckets in Luau.

Useful for rate-limits and other depletion/regeneration use cases.

## Installation

### GitHub

Download the `.rbxm` file from the [Latest Release](https://github.com/Nowoshire/LazyValueBucket/releases/latest) and place it in your desired location.

### Wally

```toml
TypeUtils = "nowoshire/lazyvaluebucket@^0.0"
```

### Rojo (Build from Source)

```bash
git clone https://github.com/Nowoshire/LazyValueBucket.git
cd LuauTypeUtils
rojo build --output "../TypeUtils.rbxm"
```