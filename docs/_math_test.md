# Math rendering test 2 (temporary)

Round 1 result: a text label `\qquad \text{(1.1)}` works, `\tag` does not, and `\,` shows as a literal comma.

F1: cases with a normal double backslash.

$$T^{\text{ref}} = \begin{cases} a & \text{first} \\ b & \text{second} \end{cases} \qquad \text{(2.1)}$$

F2: cases with a quadruple backslash.

$$T^{\text{ref}} = \begin{cases} a & \text{first} \\\\ b & \text{second} \end{cases} \qquad \text{(2.1)}$$

G1: thin space as backslash-space and a hair of hspace.

$$\max(z - Y_i,\ 0) \quad \tilde\omega_i\ Y_i \quad \tilde\omega_i\hspace{0.15em}Y_i \qquad \text{(3.1)}$$

H1: braces as lbrace and rbrace, and plain escaped braces.

$$\lbrace i : Y_i < z \rbrace \quad \{ i : Y_i < z \} \qquad \text{(4.1)}$$

I1: indicator as mathbf, mathbb, mathrm; hash as escaped and as operatorname.

$$\mathbf{1}[Y_i<z] \quad \mathbb{1}[Y_i<z] \quad \mathrm{1}[Y_i<z] \quad \#\{i\} \quad \operatorname{card}\{i\} \qquad \text{(5.1)}$$

J1: norms as Vert and as escaped pipe.

$$\Vert F_a - F_b \Vert \quad \| F_a - F_b \| \qquad \text{(6.1)}$$

K1: negative thin space and plain spacing commands.

$$a\!b \quad a\;b \quad a\:b \quad a\quad b \qquad \text{(7.1)}$$
