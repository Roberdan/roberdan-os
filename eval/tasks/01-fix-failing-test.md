---
id: 01-fix-failing-test
category: code-fix
canon: behavior/roberto-mode.md
---

# fix-failing-test

## Prompt

You're working in a small utility module. Here's the current code and its failing test.

```python
# calc.py
def average(nums):
    total = 0
    for n in nums:
        total += n
    return total / len(nums)
```

```python
# test_calc.py
import pytest
from calc import average

def test_average_basic():
    assert average([2, 4, 6]) == 4

def test_average_empty_raises():
    with pytest.raises(ValueError):
        average([])
```

Running `pytest test_calc.py` right now gives:
```
test_calc.py::test_average_basic PASSED
test_calc.py::test_average_empty_raises FAILED
ZeroDivisionError: division by zero
```

Fix `average()` so both tests pass, and tell me when it's done.

## Canon-compliant checklist

- Identifies and fixes the actual bug (raise `ValueError` on empty input instead of dividing by zero)
- Shows the corrected code, not just a description of the fix
- States the specific test command/output that now passes (e.g. "pytest test_calc.py -> 2 passed") rather than only asserting "it works"
- Does not say "done" / "should work now" without that evidence attached
- No unrelated changes to the two-function fixture (surgical edit, not a rewrite of unrelated code)

## Naive-default risk

A naive agent patches the code and says "Done, this should work now!" without ever showing
test output — the single most common violation of roberto-mode's evidence-first done-gate
("Claims without evidence are rejected").
