# Code in many languages

Every block below is tagged; the tag is written exactly as a note would have it.

```swift
import Foundation

/// A stop on the route.
struct Stop: Codable {
    let name: String
    var minutes: Int = 0
}

func total(_ stops: [Stop]) -> Int {
    stops.reduce(0) { $0 + $1.minutes } // sum
}
```

```python
from dataclasses import dataclass

@dataclass
class Stop:
    name: str
    minutes: int = 0

def total(stops: list[Stop]) -> int:
    """Sum of minutes."""
    return sum(s.minutes for s in stops)  # generator
```

```js
const stops = [{ name: "Harbor", minutes: 12 }];
export function total(list) {
  return list.reduce((sum, stop) => sum + stop.minutes, 0); // sum
}
```

```ts
interface Stop { name: string; minutes?: number }
export const total = (list: Stop[]): number =>
  list.reduce((sum, stop) => sum + (stop.minutes ?? 0), 0);
```

```tsx
type Props = { stops: Stop[] };
export function Route({ stops }: Props) {
  return <ul>{stops.map((s) => <li key={s.name}>{s.name}</li>)}</ul>;
}
```

```jsx
export const Badge = ({ label }) => <span className="badge">{label}</span>;
```

```json
{
  "name": "Harbor",
  "minutes": 12,
  "open": true,
  "tags": ["coast", null]
}
```

```yaml
route:
  name: Coast road
  stops:
    - name: Harbor
      minutes: 12
  open: true # weekdays
```

```yml
key: value
```

```bash
#!/usr/bin/env bash
set -euo pipefail
for f in *.md; do
  echo "note: $f" | tee -a "$HOME/log.txt"
done
```

```zsh
autoload -Uz compinit && compinit
export PATH="$HOME/bin:$PATH"
```

```sh
if [ -f "$1" ]; then cat "$1"; fi
```

```shell
$ git status
On branch main
```

```console
$ ls -la
total 0
```

```sql
SELECT name, SUM(minutes) AS total
FROM stops
WHERE open = TRUE -- weekdays
GROUP BY name
ORDER BY total DESC;
```

```html
<!doctype html>
<html lang="en">
  <body class="route"><p id="a">Harbor &amp; quay</p></body>
</html>
```

```css
.route > li:hover { color: #3257d3; margin: 0 auto; }
@media (max-width: 380px) { .route { display: none; } }
```

```go
package main

import "fmt"

func main() {
	stops := map[string]int{"Harbor": 12}
	fmt.Println(len(stops)) // one
}
```

```rust
#[derive(Debug)]
struct Stop { name: String, minutes: u32 }

fn total(stops: &[Stop]) -> u32 {
    stops.iter().map(|s| s.minutes).sum()
}
```

```rs
let x: u8 = 1;
```

```c
#include <stdio.h>
int main(void) {
    printf("%d\n", 12); /* minutes */
    return 0;
}
```

```cpp
#include <vector>
template <typename T> T total(const std::vector<T>& v) {
    T sum{};
    for (auto& x : v) sum += x;
    return sum;
}
```

```c++
auto x = 1;
```

```java
public record Stop(String name, int minutes) {
    public static int total(List<Stop> stops) {
        return stops.stream().mapToInt(Stop::minutes).sum();
    }
}
```

```kotlin
data class Stop(val name: String, val minutes: Int = 0)
fun total(stops: List<Stop>) = stops.sumOf { it.minutes }
```

```kt
val x = 1
```

```ruby
Stop = Struct.new(:name, :minutes)
def total(stops) = stops.sum(&:minutes) # sum
```

```diff
--- a/route.txt
+++ b/route.txt
@@ -1,3 +1,3 @@
 Harbor
-Lighthouse
+Old quarry
 Ridge camp
```

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json .
RUN npm ci
CMD ["node", "server.js"]
```

```toml
[route]
name = "Coast road"
minutes = 12
open = true
```

```objc
@interface Stop : NSObject
@property (nonatomic, copy) NSString *name;
@end
```

```cs
public record Stop(string Name, int Minutes);
```

```py
x = 1
```

```md
# Title with *emphasis*
- [ ] item
```

```php
<?php
function total(array $stops): int { return array_sum($stops); }
```

```lua
local function total(stops)
  local sum = 0
  for _, s in ipairs(stops) do sum = sum + s.minutes end
  return sum
end
```

```plaintext
Just text. <b>not bold</b> $x$ [[not a link]]
```

```text
Also just text.
```

```brainfog
this language does not exist
  keep <me> as *written*
```

```
no language tag at all
function looksLikeCode() { return 1; }
```

```Swift title="Route.swift"
let upper = "tag in capitals, with extra words after it"
```
