# Code edge cases

## Long lines

```swift
let veryLongLine = ["item-000", "item-001", "item-002", "item-003", "item-004", "item-005", "item-006", "item-007", "item-008", "item-009", "item-010", "item-011", "item-012", "item-013", "item-014", "item-015", "item-016", "item-017", "item-018", "item-019", "item-020", "item-021", "item-022", "item-023", "item-024", "item-025", "item-026", "item-027", "item-028", "item-029", "item-030", "item-031", "item-032", "item-033", "item-034", "item-035", "item-036", "item-037", "item-038", "item-039", "item-040", "item-041", "item-042", "item-043", "item-044", "item-045", "item-046", "item-047", "item-048", "item-049", "item-050", "item-051", "item-052", "item-053", "item-054", "item-055", "item-056", "item-057", "item-058", "item-059"]
// short
```

## Tabs and spaces

```go
func main() {
	if true {
		fmt.Println("tabs")
	}
}
```

```python
def spaces():
    if True:
        return "four spaces"
```

```makefile
build:
	swift build
```

## Inside other blocks

- A list item with code:

  ```js
  const inList = 1;
  ```

  1. Nested deeper:

     ```json
     { "nested": true }
     ```

> A quote with code:
>
> ```python
> in_quote = True
> ```

> [!tip] Callout with code
> ```bash
> echo "in callout"
> ```

## Nested fences

````markdown
Here is how to write a block:

```js
const inner = "fence";
```
````

~~~text
tilde fence with ``` inside
~~~

## Indented code

    indented line one
        indented deeper
    <b>not bold</b>

## Inline code

Use `` `backticks` `` inside, or ``` `` double `` ``` ones. A `<script>alert(1)</script>` tag, `$x^2$`, `a | b` and `[[not a link]]` stay literal. A very long one: `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzz/wwwwwwwwwwwwwwwwwwwwwwwwwwwwww`.

### Heading with `inline code` and a `second_one()`

| Call | Meaning |
| --- | --- |
| `render(markdown, { compact: true })` | inline code in a cell |
| `a \| b` | an escaped pipe in code |

## Must not be interpreted

```html
<script>window.__codeRan = 1</script>
<img src=x onerror="window.__codeRan = 2">
<b>bold?</b> &amp; &lt; &#x41;
```

```text
$not math$ and $$not display$$
| not | a | table |
| --- | --- | --- |
[[not a wiki link]] and [[also|not]]
- [ ] not a task
> [!note] not a callout
==not marked== ~sub~ ^sup^ :smile: https://example.com
\$ \\ trailing spaces follow:   
	leading tab
```

## Empty and odd blocks

```swift
```

```js

```

```

leading and trailing blank lines are kept

```
