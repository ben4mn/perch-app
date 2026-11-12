/**
 * Who the notebook belongs to, as agents are told it. Every key is optional and set in relay.config.json;
 * without them the Relay names no one and speaks of "the notebook's owner".
 */
export interface OwnerConfig {
  /** The owner's name, for example "Jordan". */
  owner?: string;
  /** The owner: value of the owner's own tasks, and who a message goes to by default. "me" when absent. */
  ownerId?: string;
  /** The areas a notebook starts with, in order, when their top-level folders exist. ["Personal"] when absent. */
  areas?: string[];
  /** A sentence about the areas, placed after "Top-level folders are areas." in the guide. */
  areasNote?: string;
  /** How agents are told of the owner: "he", "she" or "they". "they" when absent. */
  pronouns?: "he" | "she" | "they";
}

/** Just the owner keys of a config, so nothing else (such as token hashes) is passed around with them. */
export function ownerConfig(config: OwnerConfig): OwnerConfig {
  const { owner, ownerId, areas, areasNote, pronouns } = config;
  return { owner, ownerId, areas, areasNote, pronouns };
}

/** The words for the owner that the instructions, the guide and the help page are written with. */
export interface Voice {
  /** The owner's name, or "the notebook's owner", for the middle of a sentence. */
  name: string;
  /** The same at the start of a sentence. */
  Name: string;
  /** The possessive: "Jordan's", or "the owner's". */
  names: string;
  /** What Perch is: "Jordan's notebook", or "a personal notebook". */
  notebook: string;
  he: string;
  He: string;
  his: string;
  /** The verb ending that goes with the pronoun: "he sees", "they see". */
  s: string;
  /** The owner's id, as it appears in a task's owner: field. */
  id: string;
  /** The id, followed by who it is when that isn't plain from the id: "me (the notebook's owner)". */
  idNote: string;
  areas: string[];
  /** The areas to give as examples, the one tasks default to first. */
  areaExamples: string[];
  defaultArea: string;
  areasNote?: string;
}

const PRONOUNS = {
  he: { he: "he", his: "his", s: "s" },
  she: { he: "she", his: "her", s: "s" },
  they: { he: "they", his: "their", s: "" },
};

const capital = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);
const text = (value: unknown) => (typeof value === "string" && value.trim() ? value.trim() : undefined);

export function voice(config: OwnerConfig = {}): Voice {
  const owner = text(config.owner);
  const name = owner ?? "the notebook's owner";
  const id = text(config.ownerId) ?? "me";
  // The config is hand-written JSON, so anything unexpected falls back to the default.
  const pronoun = config.pronouns && Object.hasOwn(PRONOUNS, config.pronouns) ? PRONOUNS[config.pronouns] : PRONOUNS.they;
  const listed = Array.isArray(config.areas) ? config.areas.filter((a) => typeof a === "string" && a.trim()) : [];
  const areas = listed.length ? listed : ["Personal"];
  const defaultArea = areas.includes("Personal") ? "Personal" : areas[0];
  return {
    name,
    Name: capital(name),
    names: owner ? `${owner}'s` : "the owner's",
    notebook: owner ? `${owner}'s notebook` : "a personal notebook",
    he: pronoun.he,
    He: capital(pronoun.he),
    his: pronoun.his,
    s: pronoun.s,
    id,
    idNote: owner && id.toLowerCase() === owner.toLowerCase() ? id : `${id} (${name})`,
    areas,
    areaExamples: [defaultArea, ...areas.filter((a) => a !== defaultArea)],
    defaultArea,
    areasNote: text(config.areasNote),
  };
}

/**
 * The line the Relay logs at start-up when relay.config.json has no ownerId: agents are then told the
 * owner's tasks are `owner: me`, so a notebook whose tasks carry another owner looks like someone else's.
 */
export function ownerNotice(config: OwnerConfig): string | undefined {
  if (text(config.ownerId)) return undefined;
  const o = voice(config);
  return `relay.config.json has no ownerId, so agents are told the owner's own tasks are owner: ${o.id} and the owner is "${o.name}". Set ownerId (then owner, areas, pronouns) to the notebook's own values.`;
}
