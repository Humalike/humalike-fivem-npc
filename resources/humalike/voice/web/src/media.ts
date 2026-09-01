import { LocalTrackPublication, RemoteAudioTrack, Room, RoomEvent, Track, type RemoteParticipant, type RemoteTrackPublication, type TrackPublication } from "livekit-client";
import type { Route } from "./protocol";
import { publicationSourceId } from "./publication-source.mjs";

export type MediaStatus = "idle" | "connecting" | "connected" | "closed" | "error";

export class MediaClient {
  readonly room = new Room({ adaptiveStream: false, dynacast: false });
  #routes = new Map<string, Route>();
  #publication: LocalTrackPublication | null = null;
  #elements = new Map<string, { track: RemoteAudioTrack; element: HTMLAudioElement }>();

  constructor(
    private readonly expectedServerId: string,
    private readonly onTrack: (identity: string, stream: MediaStream) => void,
    private readonly onTrackRemoved: (identity: string) => void,
    private readonly onStatus: (status: MediaStatus) => void,
  ) {
    this.room.on(RoomEvent.TrackPublished, (publication, participant) => this.#applyPublication(publication, participant.identity));
    this.room.on(RoomEvent.TrackSubscribed, (track, publication, participant) => {
      const sourceId = this.#sourceId(publication, participant.identity);
      if (sourceId && track instanceof RemoteAudioTrack && !publication.isMuted
        && this.#routes.has(sourceId)) this.#attach(sourceId, track);
    });
    this.room.on(RoomEvent.TrackUnsubscribed, (_track, publication, participant) => {
      const sourceId = this.#sourceId(publication, participant.identity);
      if (sourceId) this.#detach(sourceId);
    });
    this.room.on(RoomEvent.TrackMuted, (publication, participant) => {
      const sourceId = this.#sourceId(publication, participant.identity);
      if (sourceId) this.#detach(sourceId);
    });
    this.room.on(RoomEvent.TrackUnmuted, (publication, participant) => {
      const sourceId = this.#sourceId(publication, participant.identity);
      if (sourceId && publication.track instanceof RemoteAudioTrack
        && this.#routes.has(sourceId)) this.#attach(sourceId, publication.track);
    });
    this.room.on(RoomEvent.ParticipantDisconnected, (participant) => {
      for (const publication of participant.audioTrackPublications.values()) {
        const sourceId = this.#sourceId(publication, participant.identity);
        if (sourceId) this.#detach(sourceId);
      }
    });
    this.room.on(RoomEvent.Disconnected, () => {
      for (const identity of [...this.#elements.keys()]) this.#detach(identity);
      this.onStatus("closed");
    });
  }

  async connect(url: string, token: string): Promise<void> {
    this.onStatus("connecting");
    try { await this.room.connect(url, token, { autoSubscribe: false }); this.onStatus("connected"); this.#reconcile(); }
    catch (error) { this.onStatus("error"); throw error; }
  }

  async publish(track: MediaStreamTrack): Promise<void> {
    track.enabled = false;
    this.#publication = await this.room.localParticipant.publishTrack(track, { source: Track.Source.Microphone, dtx: true, red: true });
  }

  async setTransmitting(active: boolean): Promise<boolean> {
    if (!this.#publication) return false;
    if (active) await this.#publication.unmute(); else await this.#publication.mute();
    return true;
  }

  setRoutes(routes: Route[]): void {
    const next = new Map(routes.map((route) => [route.sourceId, route]));
    for (const identity of this.#routes.keys()) if (!next.has(identity)) this.#detach(identity);
    this.#routes = next;
    this.#reconcile();
  }

  disconnect(): void {
    this.#publication?.track?.stop(); this.#publication = null;
    for (const identity of this.#elements.keys()) this.#detach(identity);
    this.room.disconnect();
  }

  #reconcile(): void { for (const participant of this.room.remoteParticipants.values()) this.#applyParticipant(participant); }
  #applyParticipant(participant: RemoteParticipant): void { for (const publication of participant.audioTrackPublications.values()) this.#applyPublication(publication, participant.identity); }
  #applyPublication(publication: RemoteTrackPublication, identity: string): void {
    const sourceId = this.#sourceId(publication, identity);
    const subscribe = sourceId !== null && this.#routes.has(sourceId);
    if (publication.isSubscribed !== subscribe) {
      publication.setSubscribed(subscribe);
    }
  }
  #sourceId(publication: TrackPublication, participantIdentity: string): string | null {
    return publicationSourceId(participantIdentity, publication.trackName,
      publication.source, this.expectedServerId);
  }
  #attach(identity: string, track: RemoteAudioTrack): void {
    this.#detach(identity);
    const element = document.createElement("audio"); element.autoplay = true; element.hidden = true;
    track.attach(element); element.defaultMuted = true; element.muted = true; element.volume = 0; document.body.append(element);
    if (!(element.srcObject instanceof MediaStream)) { track.detach(element); element.remove(); return; }
    this.#elements.set(identity, { track, element });
    this.onTrack(identity, element.srcObject);
  }
  #detach(identity: string): void {
    const remote = this.#elements.get(identity); if (!remote) return;
    remote.track.detach(remote.element); remote.element.remove(); this.#elements.delete(identity);
    this.onTrackRemoved(identity);
  }
}
