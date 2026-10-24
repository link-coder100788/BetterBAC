//! Usage: whisper_quantize <model.safetensors> <out.gguf>
//!
//! 2-D weight matrices whose rows fit Q8_0 blocks become Q8_0; everything
//! else (biases, layer norms, conv kernels) stays f32, which is what
//! candle's quantized Whisper expects.

use anyhow::{Context, Result};
use candle_core::quantized::{gguf_file, GgmlDType, QTensor};
use candle_core::{DType, Device};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let [_, input, output] = args.as_slice() else {
        anyhow::bail!("usage: whisper_quantize <model.safetensors> <out.gguf>");
    };

    let tensors = candle_core::safetensors::load(input, &Device::Cpu)
        .with_context(|| format!("reading {input}"))?;
    let mut names: Vec<&String> = tensors.keys().collect();
    names.sort();

    let block = GgmlDType::Q8_0.block_size();
    let mut quantized = Vec::with_capacity(names.len());
    let (mut q8, mut f32s) = (0, 0);
    for name in names {
        let t = tensors[name].to_dtype(DType::F32)?;
        let dims = t.dims();
        let dtype = if dims.len() == 2 && dims[1] % block == 0 {
            q8 += 1;
            GgmlDType::Q8_0
        } else {
            f32s += 1;
            GgmlDType::F32
        };
        quantized.push((name.as_str(), QTensor::quantize(&t, dtype)?));
    }

    let refs: Vec<(&str, &QTensor)> = quantized.iter().map(|(n, t)| (*n, t)).collect();
    let mut out = std::fs::File::create(output).with_context(|| format!("creating {output}"))?;
    gguf_file::write(&mut out, &[], &refs)?;
    println!("wrote {output}: {q8} Q8_0 tensors, {f32s} f32 tensors");
    Ok(())
}
