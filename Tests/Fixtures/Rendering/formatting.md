# Colour and formatting

The editor writes these as small pieces of HTML inside Markdown.

## Text colour

<span style="color: #D94F3D">red</span> <span style="color: #E8843C">orange</span> <span style="color: #C99A1B">amber</span> <span style="color: #3F9B5B">green</span> <span style="color: #1F9E96">teal</span> <span style="color: #3B82D9">blue</span> <span style="color: #6B5BD2">indigo</span> <span style="color: #A855C7">purple</span> <span style="color: #D4588F">pink</span> <span style="color: #7A7F87">gray</span>

Hard cases: <span style="color: #FFFFFF">white</span> <span style="color: #000000">black</span> <span style="color: #FFF36B">pale yellow</span> <span style="color: #1B1F4B">deep navy</span> <span style="color: rgb(200, 30, 30)">rgb red</span> <span style="color: hsl(210, 80%, 45%)">hsl blue</span> <span style="color: rebeccapurple">named</span>

Markdown inside: <span style="color: #3B82D9">**bold**, *italic*, `code` and [[Wiki Target]]</span>

## Highlight

==plain highlight== and <mark style="background-color: #D94F3D">red</mark> <mark style="background-color: #E8843C">orange</mark> <mark style="background-color: #C99A1B">amber</mark> <mark style="background-color: #3F9B5B">green</mark> <mark style="background-color: #1F9E96">teal</mark> <mark style="background-color: #3B82D9">blue</mark> <mark style="background-color: #6B5BD2">indigo</mark> <mark style="background-color: #A855C7">purple</mark> <mark style="background-color: #D4588F">pink</mark> <mark style="background-color: #7A7F87">gray</mark>

Highlight with **bold** inside: <mark style="background-color: #3F9B5B">**bold** and [[Wiki Target]]</mark>

## Underline and size

<u>underlined</u>, <span style="font-size: 0.85em">smaller</span>, normal, <span style="font-size: 1.15em">larger</span>, <span style="font-size: 1.3em">large</span>, <span style="font-size: 1.6em">largest</span>.

Combined: <span style="color: #6B5BD2"><u>**indigo bold underline**</u></span> and <span style="font-size: 1.3em"><span style="color: #D94F3D">large red</span></span>.

## Alignment

<div align="center">

Centered paragraph with **bold** and a [[Wiki Target]].

</div>

<div align="right">

Right aligned paragraph.

- and a list

</div>

## In other blocks

### Heading with <span style="color: #1F9E96">teal</span> and <mark style="background-color: #D4588F">pink</mark>

- list item <span style="color: #D94F3D">red</span> and <u>underline</u>
- [ ] task <mark style="background-color: #3B82D9">blue mark</mark>

> quote <span style="color: #3F9B5B">green</span> <span style="font-size: 1.3em">large</span>

> [!tip] Callout <span style="color: #A855C7">purple title</span>
> body <span style="color: #E8843C">orange</span> <mark style="background-color: #C99A1B">amber</mark>

| Cell | Value |
| --- | --- |
| <span style="color: #D94F3D">red cell</span> | <mark style="background-color: #1F9E96">teal mark</mark> <u>u</u> |

## Rejected styles

<span style="font-size: 5em">too big stays normal</span> <span style="font-size: 0.2em">too small stays normal</span> <span style="font-size: 20px">px stays normal</span> <span style="color: #12345">bad hex stays normal</span>

## Aligned blocks with more in them

<div align="center">

### A centred heading

- first item
- second item, a little longer

1. numbered

- [ ] a task

> a quote

| A | B |
| --- | --- |
| 1 | 2 |

</div>

<div align="right">

### A right-aligned heading

- a loose item

- another loose item

- [x] a done task

</div>

## Text on highlights

<mark style="background-color: #D94F3D">plain text, <span style="color: #D94F3D">red on red</span>, <span style="color: #FFFFFF">white</span>, <span style="color: #000000">black</span></mark> <mark style="background-color: #1B1F4B">on deep navy</mark> <mark style="background-color: #FFF36B">on pale yellow, <span style="color: #C99A1B">amber</span></mark>

> <span style="color: #A855C7">[!tip] A callout whose whole title line is coloured</span>
> and its body
