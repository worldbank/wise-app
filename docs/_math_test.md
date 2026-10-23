# Math rendering test (temporary)

Variant A: number written inside the formula with a text label, no tag.

$$\bar Y = \sum_i \tilde\omega_i Y_i, \qquad \text{Total} = \sum_i \omega_i Y_i \qquad \text{(1.1)}$$

Variant B: tag after an aligned block.

$$\begin{aligned}\bar Y &= \sum_i \tilde\omega_i Y_i, \\ \text{Total} &= \sum_i \omega_i Y_i\end{aligned} \tag{1.1}$$

Variant C: tag on a single short formula.

$$\bar Y = \sum_i \tilde\omega_i Y_i \tag{1.1}$$

Variant D: the original form of equation (1.2), tag at the end.

$$P_0 = \sum_i \tilde\omega_i\,\mathbb{1}[Y_i < z], \qquad P_1 = \sum_i \tilde\omega_i\,\frac{\max(z-Y_i,\,0)}{z} \tag{1.2}$$

Variant E: equation (1.2) with the number as a text label.

$$P_0 = \sum_i \tilde\omega_i\,\mathbb{1}[Y_i < z], \qquad P_1 = \sum_i \tilde\omega_i\,\frac{\max(z-Y_i,\,0)}{z} \qquad \text{(1.2)}$$
