# Rafter sizing

Worksheet for module 3. Simply supported rafter, uniform load, check bending and then deflection.

## Load on one rafter

$$
w = (g_k + q_k) \times s
$$

with $g_k = 0.75$ kN/m² dead load, $q_k = 0.75$ kN/m² snow, and rafter spacing $s = 0.4$ m, so $w = 0.6$ kN/m. Timber is C24, and Owen wants the lower stiffness, $E = 7.4$ kN/mm².

## Bending

$$
M = \frac{w L^2}{8}, \qquad \sigma = \frac{M}{Z}, \qquad Z = \frac{b d^2}{6}
$$

For a 3.2 m span: $M = 0.6 \times 3.2^2 / 8 = 0.77$ kNm.

## Deflection

$$
\delta = \frac{5 w L^4}{384 E I}, \qquad I = \frac{b d^3}{12}, \qquad \delta_{\text{limit}} = \frac{L}{250}
$$

| Section (mm) | $Z$ (cm³) | $\sigma$ (N/mm²) | $\delta$ (mm) | OK? |
| --- | ---: | ---: | ---: | --- |
| 47 x 125 | 122 | 6.3 | 14.5 | No, limit is 12.8 |
| 47 x 150 | 176 | 4.4 | 8.4 | Yes |
| 47 x 175 | 240 | 3.2 | 5.3 | Yes, but heavy |

Deflection decides it, not bending. That keeps happening and Owen says it's the point of the exercise.

Questions 4 to 7 still to do.
