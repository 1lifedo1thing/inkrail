export const soundProfiles = [
    ['classic', 'Classic', 'Loud Hermes Precisa 305 manual clacks'],
    ['soft', 'Soft', 'Damped Hermes 3000 keys'],
    ['royal', 'Royal', 'Royal Quiet De Luxe keys and carriage'],
    ['vintage', 'Vintage', 'Clatter from a 1930s manual'],
    ['portable', 'Portable', 'Hermes Baby keys and carriage'],
    ['electric', 'Electric', 'Powered IBM Selectric II strikes']
];

const styles = new Set(soundProfiles.map(([id]) => id));
export function canonicalSound(style) {
    if (style === 'office') return 'royal';
    if (style === 'crisp') return 'vintage';
    return styles.has(style) ? style : 'classic';
}
