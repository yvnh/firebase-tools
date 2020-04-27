import * as api from "../api";

const VERSION = "v1";

/**
 * Creates a pubsub topic.
 * @param name topic to create.
 */
export async function createTopic(name: string): Promise<void> {
  await api.request("PUT", `/${VERSION}/${name}`, {
    auth: true,
    origin: api.pubsubOrigin,
    data: { labels: { deployment: "firebase-schedule" } },
  });
}

/**
 * Deletes a pubsub topic.
 * @param name topic to delete.
 */
export async function deleteTopic(name: string): Promise<void> {
  await api.request("DELETE", `/${VERSION}/${name}`, {
    auth: true,
    origin: api.pubsubOrigin,
  });
}
