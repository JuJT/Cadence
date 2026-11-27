import { useEffect, useRef, useState } from "react";
import { useTheme } from "expo-router/react-navigation";
import { Alert, TextInput, View } from "react-native";

import { SchoolAttachments, SchoolCard, SchoolContent, SchoolPage, SchoolRow, useSchoolManager } from "@/components/pronote/SchoolPage";
import { Chat, Message, Recipient } from "@/services/shared/chat";
import { Capabilities } from "@/services/shared/types";
import { Services } from "@/stores/account/types";
import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";

export default function PronoteDiscussions() {
  const { manager, revision, accountId } = useSchoolManager();
  const { colors } = useTheme();
  const [chats, setChats] = useState<Chat[]>([]);
  const [messages, setMessages] = useState<Message[]>([]);
  const [selected, setSelected] = useState<Chat>();
  const [canReply, setCanReply] = useState(false);
  const [compose, setCompose] = useState<string>();
  const [recipients, setRecipients] = useState<Recipient[]>([]);
  const [chosen, setChosen] = useState<Recipient[]>([]);
  const [search, setSearch] = useState("");
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [loading, setLoading] = useState(true);
  const [failure, setFailure] = useState("");
  const [reload, setReload] = useState(0);
  const [sending, setSending] = useState(false);
  const sendInFlight = useRef(false);
  const activeAccount = useRef(accountId);
  activeAccount.current = accountId;

  function closeDetail() {
    setSelected(undefined);
    setCompose(undefined);
    setCanReply(false);
    setChosen([]);
    setSearch("");
    setSubject("");
    setBody("");
    setFailure("");
  }

  useEffect(() => {
    setChats([]);
    setMessages([]);
    setRecipients([]);
    closeDetail();
  }, [accountId]);

  useEffect(() => {
    if (!manager) return;
    let active = true;
    setLoading(true);
    setFailure("");
    if (compose) {
      setRecipients([]);
      manager.getRecipientsAvailableForNewChat(compose)
        .then(result => { if (active) setRecipients(result.sort((a, b) => a.name.localeCompare(b.name, "fr"))); })
        .catch(() => { if (active) setFailure("La liste des destinataires n’a pas pu être chargée."); })
        .finally(() => { if (active) setLoading(false); });
    } else if (selected) {
      setMessages([]);
      setCanReply(false);
      Promise.allSettled([
        manager.getChatMessages(selected), manager.canReplyToChat(selected),
      ]).then(([result, reply]) => {
        if (!active) return;
        if (result.status === "fulfilled") {
          setMessages(result.value.sort((a, b) => a.date.getTime() - b.date.getTime()));
        } else setFailure("Les messages n’ont pas pu être chargés.");
        if (reply.status === "fulfilled") setCanReply(reply.value);
        setLoading(false);
      });
    } else {
      const services = manager.getAccount().services.filter(service => service.serviceId === Services.PRONOTE);
      const clients = manager.getAvailableClients(Capabilities.CHAT_READ);
      const ids = services.filter(service => clients.some(client => "accountId" in client && client.accountId === service.id));
      if (!ids.length) {
        setFailure("Les discussions PRONOTE sont indisponibles pour ce compte.");
        setLoading(false);
        return;
      }
      Promise.allSettled(ids.map(service => manager.getChats(service.id))).then(results => {
        if (!active) return;
        setChats(results.flatMap(result => result.status === "fulfilled" ? result.value : [])
          .sort((a, b) => b.date.getTime() - a.date.getTime()));
        if (results.some(result => result.status === "rejected") || manager.getFailures(Capabilities.CHAT_READ).length) {
          setFailure("Certaines discussions n’ont pas pu être actualisées.");
        }
        setLoading(false);
      });
    }
    return () => { active = false; };
  }, [manager, revision, compose, selected, reload]);

  function refresh() { setReload(value => value + 1); }
  const composeClients = manager?.getAvailableClients(Capabilities.CHAT_CREATE);
  const canCompose = manager?.getAccount().services.find(service => service.serviceId === Services.PRONOTE &&
    composeClients?.some(client => "accountId" in client && client.accountId === service.id));

  function confirmSend() {
    const text = body.trim();
    if (!manager || sendInFlight.current || !text) return;
    const accountAtSend = accountId;
    Alert.alert(compose ? "Envoyer la discussion ?" : "Envoyer la réponse ?",
      compose ? "À " + chosen.map(recipient => recipient.name).join(", ") : selected?.subject, [
        { text: "Annuler", style: "cancel" },
        {
          text: "Envoyer",
          onPress: async () => {
            if (sendInFlight.current || activeAccount.current !== accountAtSend) return;
            sendInFlight.current = true;
            setSending(true);
            try {
              if (compose) await manager.createMail(compose, subject, text, chosen);
              else if (selected && canReply) await manager.sendMessageInChat(selected, text);
              if (activeAccount.current !== accountAtSend) return;
              if (compose) closeDetail();
              else setBody("");
              refresh();
            } catch {
              if (activeAccount.current === accountAtSend) {
                Alert.alert("Envoi non confirmé", "Vérifiez le fil dans PRONOTE avant de réessayer.");
              }
            } finally {
              sendInFlight.current = false;
              setSending(false);
            }
          },
        },
      ]);
  }

  const field = {
    padding: 12, borderRadius: 12, borderWidth: 1, borderColor: colors.border,
    backgroundColor: colors.card, color: colors.text, fontSize: 16, minHeight: 48,
  };
  const allowedServices = manager?.getAccount().services.map(service => service.id) ?? [];
  const openChat = selected && allowedServices.includes(selected.createdByAccount) ? selected : undefined;
  const newChat = compose && allowedServices.includes(compose);
  if (newChat || openChat) {
    const matches = recipients.filter(item => item.name.toLocaleLowerCase("fr").includes(search.toLocaleLowerCase("fr")));
    return (
      <SchoolPage title={newChat ? "Nouvelle discussion" : openChat?.subject || "Discussion"} loading={loading} refresh={refresh}>
        <Button label="Retour aux discussions" variant="text" onPress={closeDetail} disabled={sending} />
        {failure && <Typography color="textSecondary">{failure}</Typography>}
        {newChat && (
          <>
            <TextInput style={field} accessibilityLabel="Objet" placeholder="Objet" placeholderTextColor={colors.text}
              editable={!sending} maxLength={200} value={subject} onChangeText={setSubject} />
            <TextInput style={field} accessibilityLabel="Rechercher un destinataire" placeholder="Rechercher un destinataire"
              placeholderTextColor={colors.text} editable={!sending} value={search} onChangeText={setSearch} />
            <Typography color="textSecondary">{chosen.length ? chosen.map(item => item.name).join(", ") : "Sélectionnez un destinataire."}</Typography>
            {matches.slice(0, 24).map(recipient => {
              const checked = chosen.some(item => item.id === recipient.id);
              return (
                <SchoolRow key={recipient.id} title={recipient.name} selected={checked} onPress={() => {
                  if (sending) return;
                  setChosen(items => checked ? items.filter(item => item.id !== recipient.id) : items.length < 20 ? [...items, recipient] : items);
                }} />
              );
            })}
            {!loading && !matches.length && <Typography>Aucun destinataire disponible.</Typography>}
          </>
        )}
        {openChat && (
          <>
            {!loading && !failure && !messages.length && <Typography>Aucun message.</Typography>}
            {messages.map(message => (
              <SchoolCard key={message.id}>
                <Typography variant="title">{message.author || "PRONOTE"}</Typography>
                <Typography variant="caption" color="textSecondary">{message.date.toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" })}</Typography>
                <SchoolContent content={message.content} />
                <SchoolAttachments files={message.attachments} />
              </SchoolCard>
            ))}
          </>
        )}
        {(newChat || canReply) && (
          <View style={{ gap: 10 }}>
            <TextInput multiline textAlignVertical="top" style={[field, { minHeight: 110 }]}
              accessibilityLabel={newChat ? "Message" : "Réponse"} placeholder={newChat ? "Message" : "Réponse"}
              placeholderTextColor={colors.text} editable={!sending} maxLength={20000} value={body} onChangeText={setBody} />
            <Button label={sending ? "Envoi…" : "Envoyer"} onPress={confirmSend}
              disabled={sending || !body.trim() || Boolean(newChat && (!chosen.length || !subject.trim()))} />
          </View>
        )}
      </SchoolPage>
    );
  }

  const visibleChats = chats.filter(chat => chat.provider === "pronote" && allowedServices.includes(chat.createdByAccount));
  return (
    <SchoolPage title="Discussions" loading={loading} refresh={refresh}>
      {canCompose && <Button label="Nouvelle discussion" onPress={() => setCompose(canCompose.id)} />}
      {failure && <Typography color="textSecondary">{failure}</Typography>}
      {!loading && !failure && visibleChats.length === 0 && <Typography>Aucune discussion reçue.</Typography>}
      {visibleChats.map(chat => (
        <SchoolRow key={chat.createdByAccount + ":" + chat.id} title={chat.subject || "Discussion"}
          caption={[chat.creator || chat.recipient, chat.date.toLocaleDateString("fr-FR", { dateStyle: "medium" })].filter(Boolean).join(" · ")}
          onPress={() => setSelected(chat)} />
      ))}
    </SchoolPage>
  );
}
