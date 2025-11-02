import { AsyncLocalStorage } from 'async_hooks';

export interface RequestContextData {
  request_id: string;
  http_method: string;
  http_path: string;
  http_query?: string;
  client_ip?: string;
  user_id?: string;
  status_code?: number;
  duration_ms?: number;
}

export const requestContext = new AsyncLocalStorage<RequestContextData>();

export function getCurrentUserId(): string | undefined {
  const store = requestContext.getStore();
  return store?.user_id;
}
