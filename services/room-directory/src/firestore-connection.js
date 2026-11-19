import {Firestore} from "@google-cloud/firestore";
import {getVercelOidcToken} from "@vercel/oidc";
import {ExternalAccountClient, GoogleAuth} from "google-auth-library";

let firestore;

export function getScoreFirestore() {
  if (firestore) return firestore;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!projectId) throw new Error("FIREBASE_PROJECT_ID is required");
  const settings = {projectId, preferRest: !process.env.FIRESTORE_EMULATOR_HOST};
  if (process.env.VERCEL) {
    const provider = process.env.GCP_WORKLOAD_IDENTITY_PROVIDER;
    const account = process.env.GCP_SERVICE_ACCOUNT_EMAIL;
    if (!provider || !account || process.env.FIRESTORE_EMULATOR_HOST) {
      throw new Error("Production Firestore identity is not configured");
    }
    const workload = ExternalAccountClient.fromJSON({
      type: "external_account",
      audience: "//iam.googleapis.com/" + provider,
      subject_token_type: "urn:ietf:params:oauth:token-type:jwt",
      token_url: "https://sts.googleapis.com/v1/token",
      scopes: ["https://www.googleapis.com/auth/datastore"],
      service_account_impersonation_url: `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${account}:generateAccessToken`,
      subject_token_supplier: {getSubjectToken: () => getVercelOidcToken()}
    });
    settings.auth = new GoogleAuth({projectId, authClient: workload});
  }
  firestore = new Firestore(settings);
  return firestore;
}
