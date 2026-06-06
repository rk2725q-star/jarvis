import sys
import json

sys.stdout.reconfigure(encoding='utf-8')

transcript_path = r"C:\Users\manit\.gemini\antigravity-ide\brain\bc8a8881-22fb-466e-8815-c8f7953c7723\.system_generated\logs\transcript.jsonl"

with open(transcript_path, 'r', encoding='utf-8') as f:
    for i, line in enumerate(f):
        if "ai_router.dart" in line and ("replace_file_content" in line or "multi_replace_file_content" in line) and "PLANNER_RESPONSE" in line:
            try:
                step = json.loads(line)
                tool_calls = step.get('tool_calls', [])
                for call in tool_calls:
                    name = call.get('name') or call.get('ToolName')
                    args = call.get('args') or call.get('Arguments') or {}
                    target = args.get('TargetFile') or args.get('Target') or ""
                    if "ai_router.dart" in target:
                        print(f"=== Line {i+1}, Step {step.get('step_index')}, Tool: {name} ===")
                        chunks = args.get('ReplacementChunks')
                        if chunks:
                            try:
                                if isinstance(chunks, str):
                                    chunks = json.loads(chunks, strict=False)
                                print("ReplacementChunks:")
                                print(json.dumps(chunks, indent=2))
                            except Exception as ex:
                                print("Error parsing chunks:", ex)
                                print("Chunks raw:", chunks[:500])
                        else:
                            print("StartLine:", args.get('StartLine'))
                            print("EndLine:", args.get('EndLine'))
                            print("TargetContent:")
                            print(args.get('TargetContent'))
                            print("ReplacementContent:")
                            print(args.get('ReplacementContent'))
                        print("=" * 60)
            except Exception as e:
                print(f"Outer error at line {i+1}:", e)
