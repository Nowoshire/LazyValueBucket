# Lazy Value Bucket

An implementation of lazily evaluated token buckets in Luau.

Useful for rate-limits and other depletion/regeneration use cases.

## Installation

### Pre-built RBXM

Download the `.rbxm` file from the [Latest Release](https://github.com/Nowoshire/LazyValueBucket/releases/latest), and place it in your desired location.

### Wally

Add the following to your `wally.toml` dependencies:

```toml
ValueBucket = "nowoshire/lazyvaluebucket@1.0.0"
```

### Rojo (Build from Source)

```bash
git clone https://github.com/Nowoshire/LazyValueBucket.git
cd LazyValueBucket
rojo build --output "ValueBucket.rbxm"
```
